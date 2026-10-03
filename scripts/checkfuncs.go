// Command checkfuncs checks that the accelerators in the slots compute what
// they should.  It sends each slot requests of known data, works out on the
// host what the unit there must answer, and compares the two word by word.
// testfuncs.go only tells which RM answers; this one checks the arithmetic.
//
//	go run scripts/checkfuncs.go -unit top_k -slots 0,1,2,3
//	go run scripts/checkfuncs.go -unit log -slots 2 -sizes 128,4096
//
// The slots must already hold the unit.  The full image starts every slot
// with the top_k it was built with, which a newer partial may have replaced,
// so load the partials first; scripts/checkfuncs.sh loads and checks every
// unit in every cell.
//
// What each unit answers (kernels/user_krnl/apps/<unit>/src/rtl/<unit>_core.v):
//
//	top_k         one 64-byte line: the 16 largest 32-bit words of the
//	              request, compared unsigned, largest first.  Word j is zeroed
//	              where bit j of the header's top config is clear, and bits
//	              1:0 of that field are the FIRST and LAST flags, so a request
//	              whose header does not carry LAST gets word 1 zeroed.
//	log           ln(x / (1 - x)) of every single-precision value, one line
//	              per data line.
//	norm          (x - min) / (max - min) of every value, min and max over the
//	              whole request, one line per data line.  At most 256 data
//	              lines: norm never finishes a longer request.
//	pattern_slot  every line echoed, the header included.
//	or_slot       every line, the header included, as all ones.
//
// log and norm run on Xilinx floating-point cores, which subtract and divide
// in IEEE-754 single precision, rounded to nearest even, with subnormals
// flushed to zero.  The same steps are taken here, so norm must match bit for
// bit (-norm-ulps).  The logarithm core is not correctly rounded: its answer
// may be -log-ulps units in the last place off, or 2^-24 where it is near 0,
// the resolution of its input around 1.
//
// Request framing, as in testfuncs.go (dispatcher.v parses it):
//
//	bytes 0-55   0xff filler
//	bytes 56-59  request size, little-endian, INCLUDING the 64-byte header
//	bytes 60-61  top config; bits 1:0 are the FIRST and LAST request flags
//	bytes 62-63  workload id: workload N is slot N
//
// pkt_receiver.v takes only TCP segments of whole 64-byte lines, at most 8192
// bytes.  Each segment is one Write, and -gap passes before the next, so that
// the host's stack sends it alone instead of merging it with the next one.
// Every size is sent in each framing that suits it:
//
//	whole   the header and the data in one segment, flagged FIRST|LAST
//	split   the header with the first data, the rest in -seg-byte segments,
//	        flagged FIRST: what fperf does when -X is larger than -m
//	header  the header alone, then the data, flagged FIRST: what testfuncs.go
//	        does.  dispatcher.v ends a request at a one-line segment flagged
//	        LAST, so LAST stays clear.
//
// The first pass runs one connection per slot, all slots at once.  The second
// (-conns) adds more connections per slot, with whole requests only:
// scheduler.v holds one of its four queues for every request spread over
// segments, and more than four open at once stall its input for good.
package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	defaultServerAddress = "172.24.1.52:2888"

	// One 512-bit AXI-Stream beat.
	lineBytes          = 64
	wordsPerLine       = lineBytes / 4
	requestPrefixBytes = 56

	reqFlagFirst = 0x1
	reqFlagLast  = 0x2

	defaultTopConfig = 0xffff

	// pkt_receiver.v's MAX_PACKET_BYTES: the longest segment it takes, and
	// the longest the FPGA sends.
	maxSegmentBytes = 8192
	// norm_core.v's MAX_LINES.  A request with more data lines never
	// finishes, and the slot takes nothing more until it is reloaded.
	normMaxDataLines = 256
	// The request size reaches log and norm as 16 bits (scheduler.v
	// rx_req_size), and they answer that less the header.
	maxRequestBytes = 65535 / lineBytes * lineBytes

	slotCount = 4

	// How long to wait for bytes after an answer that should have ended it.
	extraWait = time.Millisecond
	// and after a connection's last answer.
	finalWait = 100 * time.Millisecond
	// Requests in a row with no answer before a slot is given up on.
	maxSilent = 3
)

var framings = []string{"whole", "split", "header"}

// ---------------------------------------------------------------- requests

func buildHeader(totalSize int, workloadID uint16, flags byte, topConfig uint16) []byte {
	header := make([]byte, lineBytes)
	for idx := 0; idx < requestPrefixBytes; idx++ {
		header[idx] = 0xff
	}
	binary.LittleEndian.PutUint32(header[56:60], uint32(totalSize))
	binary.LittleEndian.PutUint16(header[60:62], topConfig)
	header[60] = (header[60] &^ 0x3) | (flags & 0x3)
	binary.LittleEndian.PutUint16(header[62:64], workloadID)
	return header
}

// cutsFor gives the end of every segment a request of size bytes is sent in,
// the header counted, or nil when the framing does not suit the size.
func cutsFor(framing string, size, seg, segLimit int) []int {
	var cuts []int
	switch framing {
	case "whole":
		if size > segLimit {
			return nil
		}
	case "split":
		// two segments at least, the first the header and a data line at least
		step := size / 2 / lineBytes * lineBytes
		if step > seg {
			step = seg
		}
		if step < 2*lineBytes {
			step = 2 * lineBytes
		}
		if size <= step {
			return nil
		}
		for end := step; end < size; end += step {
			cuts = append(cuts, end)
		}
	case "header":
		cuts = append(cuts, lineBytes)
		for end := lineBytes + seg; end < size; end += seg {
			cuts = append(cuts, end)
		}
	}
	return append(cuts, size)
}

type request struct {
	slot      int
	size      int // bytes, the header included
	framing   string
	shape     string
	cuts      []int
	topConfig uint16 // bytes 60-61 as sent, the flags included
	header    []byte
	data      []byte
}

func newRequest(u *unit, slot, size int, framing string, cuts []int, sh shape, rng *rand.Rand) *request {
	flags := byte(reqFlagFirst)
	if framing == "whole" {
		flags |= reqFlagLast
	}
	topConfig := uint16(defaultTopConfig)
	if u.name == "top_k" && rng.Intn(4) == 0 {
		topConfig = uint16(rng.Uint32()) // a random result mask now and then
	}
	header := buildHeader(size, uint16(slot), flags, topConfig)
	return &request{
		slot:      slot,
		size:      size,
		framing:   framing,
		shape:     sh.name,
		cuts:      cuts,
		topConfig: binary.LittleEndian.Uint16(header[60:62]),
		header:    header,
		data:      bytesOf(sh.words(rng, (size-lineBytes)/4)),
	}
}

func (r *request) bytes() []byte {
	return append(append([]byte(nil), r.header...), r.data...)
}

func (r *request) words() []uint32 { return wordsOf(r.data) }

func wordsOf(data []byte) []uint32 {
	out := make([]uint32, len(data)/4)
	for idx := range out {
		out[idx] = binary.LittleEndian.Uint32(data[idx*4:])
	}
	return out
}

func bytesOf(values []uint32) []byte {
	out := make([]byte, len(values)*4)
	for idx, value := range values {
		binary.LittleEndian.PutUint32(out[idx*4:], value)
	}
	return out
}

// ---------------------------------------------------------------- answers

func f32(w uint32) float32 { return math.Float32frombits(w) }

// ftz flushes a subnormal to the zero of its sign, as the Xilinx cores do
// with their operands and results.
func ftz(f float32) float32 {
	if b := math.Float32bits(f); b&0x7f800000 == 0 {
		return math.Float32frombits(b & 0x80000000)
	}
	return f
}

// topK is top_k_core.v: the 16 largest words, unsigned, largest first, word j
// kept only where bit j of the mask is set.
func topK(words []uint32, mask uint16) []uint32 {
	ranked := append([]uint32(nil), words...)
	sort.Slice(ranked, func(a, b int) bool { return ranked[a] > ranked[b] })
	out := make([]uint32, wordsPerLine)
	for j := 0; j < wordsPerLine && j < len(ranked); j++ {
		if mask>>uint(j)&1 != 0 {
			out[j] = ranked[j]
		}
	}
	return out
}

// logit is log_core.v: 1 - x, then x / (1 - x), then its logarithm, each
// rounded to single precision.
func logit(words []uint32) []uint32 {
	out := make([]uint32, len(words))
	for idx, w := range words {
		x := ftz(f32(w))
		d := ftz(float32(1 - x))
		q := ftz(float32(x / d))
		out[idx] = math.Float32bits(ftz(float32(math.Log(float64(q)))))
	}
	return out
}

// fkey is norm_core.v's ordering: an unsigned compare of the keys orders the
// floats, -0 below +0.
func fkey(w uint32) uint32 {
	if w&0x80000000 != 0 {
		return ^w
	}
	return w | 0x80000000
}

// norm is norm_core.v: the min and max of the request, max - min once, then
// (x - min) / (max - min) for every value, each step rounded to single
// precision.
func norm(words []uint32) []uint32 {
	lo, hi := words[0], words[0]
	for _, w := range words[1:] {
		if fkey(w) < fkey(lo) {
			lo = w
		}
		if fkey(w) > fkey(hi) {
			hi = w
		}
	}
	low := ftz(f32(lo))
	span := ftz(float32(ftz(f32(hi)) - low))
	out := make([]uint32, len(words))
	for idx, w := range words {
		diff := ftz(float32(ftz(f32(w)) - low))
		out[idx] = math.Float32bits(ftz(float32(diff / span)))
	}
	return out
}

// ---------------------------------------------------------------- data

type shape struct {
	name  string
	words func(rng *rand.Rand, n int) []uint32
}

func fill(n int, value func(idx int) uint32) []uint32 {
	out := make([]uint32, n)
	for idx := range out {
		out[idx] = value(idx)
	}
	return out
}

func floats(draw func(rng *rand.Rand) float32) func(*rand.Rand, int) []uint32 {
	return func(rng *rand.Rand, n int) []uint32 {
		return fill(n, func(int) uint32 { return math.Float32bits(draw(rng)) })
	}
}

// inside rounds draws to single precision until one falls strictly between
// 0 and 1.
func inside(draw func() float64) float32 {
	for {
		if v := float32(draw()); v > 0 && v < 1 {
			return v
		}
	}
}

var topKShapes = []shape{
	{"random", func(rng *rand.Rand, n int) []uint32 {
		return fill(n, func(int) uint32 { return rng.Uint32() })
	}},
	{"ties", func(rng *rand.Rand, n int) []uint32 {
		return fill(n, func(int) uint32 { return uint32(rng.Intn(8)) })
	}},
	{"ascending", func(rng *rand.Rand, n int) []uint32 {
		base := rng.Uint32() >> 1
		return fill(n, func(idx int) uint32 { return base + uint32(idx) })
	}},
	{"descending", func(rng *rand.Rand, n int) []uint32 {
		base := rng.Uint32() | 0x80000000
		return fill(n, func(idx int) uint32 { return base - uint32(idx) })
	}},
	{"equal", func(rng *rand.Rand, n int) []uint32 {
		v := rng.Uint32()
		return fill(n, func(int) uint32 { return v })
	}},
	{"planted", func(rng *rand.Rand, n int) []uint32 {
		// 16 large values at random places among small ones
		out := fill(n, func(int) uint32 { return rng.Uint32() >> 4 })
		for _, idx := range rng.Perm(n)[:wordsPerLine] {
			out[idx] = rng.Uint32() | 0xf0000000
		}
		return out
	}},
	{"header-like", func(rng *rand.Rand, n int) []uint32 {
		// The first data line starts with the header's 56 bytes of 0xff,
		// which only a request's first line may be taken for.
		out := fill(n, func(int) uint32 { return rng.Uint32() })
		for idx := 0; idx < requestPrefixBytes/4; idx++ {
			out[idx] = 0xffffffff
		}
		return out
	}},
}

var logSpecials = []float32{
	0.5, 0.25, 0.75, 0, 1, 2, -1, float32(math.Inf(1)),
	float32(math.NaN()), 0x1p-24, 1 - 0x1p-24, 0x1p-126, 0.1, 0.9, 1e-3, 0.999,
}

var logShapes = []shape{
	{"x in (0,1)", floats(func(rng *rand.Rand) float32 {
		return inside(rng.Float64)
	})},
	{"small x", floats(func(rng *rand.Rand) float32 {
		return inside(func() float64 { return math.Pow(10, -30*rng.Float64()) })
	})},
	{"x near 1", floats(func(rng *rand.Rand) float32 {
		return inside(func() float64 { return 1 - math.Pow(10, -1-6*rng.Float64()) })
	})},
	{"x near 1/2", floats(func(rng *rand.Rand) float32 {
		return inside(func() float64 { return 0.5 + (rng.Float64()-0.5)*1e-3 })
	})},
	{"special values", func(rng *rand.Rand, n int) []uint32 {
		// 0 and 1 give -inf and +inf; below 0, above 1, inf and NaN give NaN
		start := rng.Intn(len(logSpecials))
		return fill(n, func(idx int) uint32 {
			return math.Float32bits(logSpecials[(start+idx)%len(logSpecials)])
		})
	}},
}

var normShapes = []shape{
	{"[0,1)", floats(func(rng *rand.Rand) float32 {
		return float32(rng.Float64())
	})},
	{"[-1000,1000)", floats(func(rng *rand.Rand) float32 {
		return float32(2000*rng.Float64() - 1000)
	})},
	{"magnitudes 1e-3..1e3", floats(func(rng *rand.Rand) float32 {
		v := float32(math.Pow(10, 6*rng.Float64()-3))
		if rng.Intn(2) == 0 {
			v = -v
		}
		return v
	})},
	{"narrow [100,101)", floats(func(rng *rand.Rand) float32 {
		return float32(100 + rng.Float64())
	})},
	{"integers 0-15", floats(func(rng *rand.Rand) float32 {
		return float32(rng.Intn(16))
	})},
	{"min and max at the ends", func(rng *rand.Rand, n int) []uint32 {
		out := floats(func(rng *rand.Rand) float32 { return float32(rng.Float64()) })(rng, n)
		lo, hi := float32(-1), float32(2)
		if rng.Intn(2) == 0 {
			lo, hi = hi, lo
		}
		out[0], out[n-1] = math.Float32bits(lo), math.Float32bits(hi)
		return out
	}},
	{"all equal", func(rng *rand.Rand, n int) []uint32 {
		// max - min is 0, so every answer is 0 / 0, NaN
		v := math.Float32bits(float32(rng.Float64()))
		return fill(n, func(int) uint32 { return v })
	}},
}

var byteShapes = []shape{
	{"random", func(rng *rand.Rand, n int) []uint32 {
		return fill(n, func(int) uint32 { return rng.Uint32() })
	}},
	{"counter", func(rng *rand.Rand, n int) []uint32 {
		return fill(n, func(idx int) uint32 { return uint32(idx) })
	}},
}

// ---------------------------------------------------------------- units

type unit struct {
	name   string
	shapes []shape
	// answer is what the slot must send back.
	answer func(r *request) []byte
	// A float unit is compared value by value, within ulps units in the
	// last place, or within nearZero of it; the others byte for byte.
	float    bool
	ulps     int64
	nearZero float64
}

// unitOrder is the order answers are matched in to name what a slot holds.
var unitOrder = []string{"top_k", "log", "norm", "pattern_slot", "or_slot"}

var unitAliases = map[string]string{
	"topk": "top_k", "logit": "log", "pattern": "pattern_slot", "echo": "pattern_slot", "or": "or_slot",
}

func makeUnits(logULPs, normULPs int64) map[string]*unit {
	return map[string]*unit{
		"top_k": {
			name:   "top_k",
			shapes: topKShapes,
			answer: func(r *request) []byte { return bytesOf(topK(r.words(), r.topConfig)) },
		},
		"log": {
			name:     "log",
			shapes:   logShapes,
			answer:   func(r *request) []byte { return bytesOf(logit(r.words())) },
			float:    true,
			ulps:     logULPs,
			nearZero: 0x1p-24,
		},
		"norm": {
			name:   "norm",
			shapes: normShapes,
			answer: func(r *request) []byte { return bytesOf(norm(r.words())) },
			float:  true,
			ulps:   normULPs,
		},
		"pattern_slot": {
			name:   "pattern_slot",
			shapes: byteShapes,
			answer: func(r *request) []byte { return r.bytes() },
		},
		"or_slot": {
			name:   "or_slot",
			shapes: byteShapes,
			answer: func(r *request) []byte { return bytes.Repeat([]byte{0xff}, r.size) },
		},
	}
}

// responseBytes is how long the unit's answer to a request of size bytes is.
func responseBytes(u *unit, size int) int {
	switch u.name {
	case "top_k":
		return lineBytes
	case "log", "norm":
		return size - lineBytes
	}
	return size
}

// ---------------------------------------------------------------- compare

func isNaN(w uint32) bool { return w&0x7f800000 == 0x7f800000 && w&0x007fffff != 0 }
func isInf(w uint32) bool { return w&0x7fffffff == 0x7f800000 }

// ordinal numbers the floats in order, both zeros 0, so that two are as many
// units in the last place apart as their ordinals.
func ordinal(w uint32) int64 {
	if w&0x80000000 != 0 {
		return -int64(w & 0x7fffffff)
	}
	return int64(w)
}

type verdict struct {
	words, exact, wrong int
	maxULP              int64 // over the finite values, the accepted ones too
	notes               []string
}

// compare checks an answer of the right length against the expected one.
func compare(u *unit, r *request, want, got []byte, maxNotes int) verdict {
	var v verdict
	wantWords, gotWords := wordsOf(want), wordsOf(got)
	var in []uint32
	if u.float {
		in = r.words()
	}
	for idx, w := range wantWords {
		g := gotWords[idx]
		v.words++
		if w == g || (u.float && isNaN(w) && isNaN(g)) {
			v.exact++
			continue
		}
		ok := false
		var ulps int64
		if u.float && !isNaN(w) && !isNaN(g) && !isInf(w) && !isInf(g) {
			ulps = ordinal(w) - ordinal(g)
			if ulps < 0 {
				ulps = -ulps
			}
			if ulps > v.maxULP {
				v.maxULP = ulps
			}
			ok = ulps <= u.ulps ||
				(u.nearZero > 0 && math.Abs(float64(f32(w))-float64(f32(g))) <= u.nearZero)
		}
		if ok {
			continue
		}
		v.wrong++
		if len(v.notes) >= maxNotes {
			continue
		}
		where := fmt.Sprintf("line %d word %d", idx/wordsPerLine, idx%wordsPerLine)
		if !u.float {
			v.notes = append(v.notes, fmt.Sprintf("%s: want %08x, got %08x", where, w, g))
			continue
		}
		note := fmt.Sprintf("%s: x %v (%08x), want %v (%08x), got %v (%08x)",
			where, f32(in[idx]), in[idx], f32(w), w, f32(g), g)
		if ulps > 0 {
			note += fmt.Sprintf(", %d ulp", ulps)
		}
		v.notes = append(v.notes, note)
	}
	return v
}

// answersLike names the unit whose answer got is, or "" for none of them.
func answersLike(units map[string]*unit, r *request, got []byte) string {
	for _, name := range unitOrder {
		u := units[name]
		want := u.answer(r)
		if len(want) == len(got) && compare(u, r, want, got, 0).wrong == 0 {
			return name
		}
	}
	return ""
}

func hexWords(data []byte) string {
	parts := make([]string, 0, len(data)/4)
	for _, w := range wordsOf(data) {
		parts = append(parts, fmt.Sprintf("%08x", w))
	}
	return strings.Join(parts, " ")
}

// ---------------------------------------------------------------- the wire

// link is a connection to the design, opened when first needed and dropped
// after anything that may leave answer bytes unread.
type link struct {
	addr    string
	timeout time.Duration
	conn    net.Conn
}

func (l *link) get() (net.Conn, error) {
	if l.conn == nil {
		conn, err := net.DialTimeout("tcp", l.addr, l.timeout)
		if err != nil {
			return nil, err
		}
		l.conn = conn
	}
	return l.conn, nil
}

func (l *link) drop() {
	if l.conn != nil {
		l.conn.Close()
		l.conn = nil
	}
}

// exchange sends a request, segment by segment, and reads an answer of want
// bytes.
func exchange(conn net.Conn, r *request, want int, timeout, gap time.Duration) ([]byte, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	full := r.bytes()
	start := 0
	for idx, end := range r.cuts {
		if idx > 0 && gap > 0 {
			time.Sleep(gap)
		}
		if _, err := conn.Write(full[start:end]); err != nil {
			return nil, fmt.Errorf("sending segment %d: %w", idx, err)
		}
		start = end
	}
	got := make([]byte, want)
	if n, err := io.ReadFull(conn, got); err != nil {
		if errors.Is(err, os.ErrDeadlineExceeded) {
			return got[:n], fmt.Errorf("%d of the %d answer bytes in %v", n, want, timeout)
		}
		return got[:n], fmt.Errorf("%d of the %d answer bytes: %w", n, want, err)
	}
	return got, nil
}

// extra counts the bytes that arrive within wait: more answer than there
// should be, which would otherwise be read as the start of the next answer.
func extra(conn net.Conn, wait time.Duration) int {
	if err := conn.SetReadDeadline(time.Now().Add(wait)); err != nil {
		return 0
	}
	buf := make([]byte, 4096)
	total := 0
	for {
		n, err := conn.Read(buf)
		total += n
		if err != nil {
			return total
		}
	}
}

// readLines reads the first line on the full timeout and up to max bytes in
// all, the rest on a short wait each, stopping at the first gap.
func readLines(conn net.Conn, max int, timeout, wait time.Duration) ([]byte, error) {
	if err := conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return nil, err
	}
	got := make([]byte, lineBytes)
	if _, err := io.ReadFull(conn, got); err != nil {
		return nil, err
	}
	for len(got) < max {
		if err := conn.SetReadDeadline(time.Now().Add(wait)); err != nil {
			break
		}
		line := make([]byte, lineBytes)
		if _, err := io.ReadFull(conn, line); err != nil {
			break
		}
		got = append(got, line...)
	}
	return got, nil
}

// probeMSS connects once and returns the TCP MSS the host's stack uses
// towards the design, and the interface and MTU of the local address.
func probeMSS(addr string, timeout time.Duration) (int, string, int, error) {
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return 0, "", 0, err
	}
	defer conn.Close()
	tcp, ok := conn.(*net.TCPConn)
	if !ok {
		return 0, "", 0, fmt.Errorf("not a TCP connection")
	}
	raw, err := tcp.SyscallConn()
	if err != nil {
		return 0, "", 0, err
	}
	mss := 0
	var sockErr error
	if err := raw.Control(func(fd uintptr) {
		mss, sockErr = syscall.GetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_MAXSEG)
	}); err != nil {
		return 0, "", 0, err
	}
	if sockErr != nil {
		return 0, "", 0, sockErr
	}
	name, mtu := interfaceOf(conn.LocalAddr())
	return mss, name, mtu, nil
}

func interfaceOf(local net.Addr) (string, int) {
	addr, ok := local.(*net.TCPAddr)
	if !ok {
		return "", 0
	}
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", 0
	}
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			if ipnet, ok := a.(*net.IPNet); ok && ipnet.IP.Equal(addr.IP) {
				return iface.Name, iface.MTU
			}
		}
	}
	return "", 0
}

// ---------------------------------------------------------------- checks

type config struct {
	addr      string
	unit      *unit
	units     map[string]*unit
	sizes     []int
	reqs      int
	seg       int
	segLimit  int
	respLimit int // the longest answer that gets here, 0 for any
	conns     int
	concReqs  int
	seed      int64
	timeout   time.Duration
	gap       time.Duration
	show      int
}

type tally struct{ sent, right int }

type slotReport struct {
	slot     int
	answered string // the unit the first answer matched, "" for none
	fatal    error  // the slot was given up on

	mu       sync.Mutex
	tallies  map[string]*tally // by size/framing, and "concurrent"
	words    int               // values compared, for the float units
	exact    int
	maxULP   int64
	failures []string // the first -show wrong answers
	notes    []string
}

func tallyKey(size int, framing string) string { return fmt.Sprintf("%d/%s", size, framing) }

func (s *slotReport) record(c *config, key string, r *request, v verdict, want, got []byte, err error) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	t := s.tallies[key]
	if t == nil {
		t = &tally{}
		s.tallies[key] = t
	}
	t.sent++
	s.words += v.words
	s.exact += v.exact
	if v.maxULP > s.maxULP {
		s.maxULP = v.maxULP
	}
	if err == nil && v.wrong == 0 {
		t.right++
		return true
	}
	if len(s.failures) < c.show {
		s.failures = append(s.failures, describe(c.unit, r, v, want, got, err))
	}
	return false
}

func (s *slotReport) note(text string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.notes = append(s.notes, text)
}

func describe(u *unit, r *request, v verdict, want, got []byte, err error) string {
	var b strings.Builder
	fmt.Fprintf(&b, "  WRONG  %d-byte request, %s framing, %q data", r.size, r.framing, r.shape)
	if u.name == "top_k" {
		fmt.Fprintf(&b, ", top config 0x%04x", r.topConfig)
	}
	if err != nil {
		fmt.Fprintf(&b, ": %v\n", err)
		return b.String()
	}
	fmt.Fprintf(&b, ": %d of %d words wrong\n", v.wrong, v.words)
	if u.name == "top_k" {
		fmt.Fprintf(&b, "    want %s\n    got  %s\n", hexWords(want), hexWords(got))
		return b.String()
	}
	for _, note := range v.notes {
		fmt.Fprintf(&b, "    %s\n", note)
	}
	return b.String()
}

// run sends one request on l and checks the answer.  Anything that may leave
// answer bytes unread drops the connection, so the next request starts clean.
func (c *config) run(l *link, r *request, checkExtra bool) (verdict, []byte, []byte, error) {
	want := c.unit.answer(r)
	conn, err := l.get()
	if err != nil {
		return verdict{}, want, nil, fmt.Errorf("connecting: %w", err)
	}
	got, err := exchange(conn, r, len(want), c.timeout, c.gap)
	if err != nil {
		l.drop()
		return verdict{}, want, got, err
	}
	v := compare(c.unit, r, want, got, 4)
	if v.wrong > 0 {
		if n := extra(conn, 20*time.Millisecond); n > 0 {
			v.notes = append(v.notes, fmt.Sprintf("and %d more bytes followed the answer", n))
		}
		l.drop()
		return v, want, got, nil
	}
	if checkExtra {
		if n := extra(conn, extraWait); n > 0 {
			l.drop()
			return v, want, got, fmt.Errorf("%d bytes more than the %d-byte answer", n, len(want))
		}
	}
	return v, want, got, nil
}

// identify sends one small request and names the unit whose answer came
// back.  The first request after a flash can go unanswered, so it tries a
// few times, each on a new connection.
func (c *config) identify(slot int, rng *rand.Rand) (string, []byte, error) {
	size := 2 * lineBytes
	header := buildHeader(size, uint16(slot), reqFlagFirst|reqFlagLast, defaultTopConfig)
	r := &request{
		slot: slot, size: size, framing: "whole", shape: "probe", cuts: []int{size},
		topConfig: binary.LittleEndian.Uint16(header[60:62]),
		header:    header,
		data: bytesOf(fill(wordsPerLine, func(int) uint32 {
			return math.Float32bits(float32(0.05 + 0.9*rng.Float64()))
		})),
	}
	var last error
	for try := 0; try < maxSilent; try++ {
		conn, err := net.DialTimeout("tcp", c.addr, c.timeout)
		if err != nil {
			last = err
			continue
		}
		got, err := func() ([]byte, error) {
			defer conn.Close()
			if _, err := conn.Write(r.bytes()); err != nil {
				return nil, err
			}
			return readLines(conn, size, c.timeout, finalWait)
		}()
		if err != nil {
			last = err
			continue
		}
		return answersLike(c.units, r, got), got, nil
	}
	return "", nil, fmt.Errorf("no answer to %d tries: %v", maxSilent, last)
}

type job struct {
	size    int
	framing string
	cuts    []int
	shape   int
}

// checkSlot is the first pass: every size in every framing that suits it,
// in a shuffled order, on one connection.
func (c *config) checkSlot(slot int) *slotReport {
	s := &slotReport{slot: slot, tallies: map[string]*tally{}}
	rng := rand.New(rand.NewSource(c.seed*1000 + int64(slot)))

	name, got, err := c.identify(slot, rng)
	if err != nil {
		s.fatal = err
		return s
	}
	s.answered = name
	switch name {
	case c.unit.name:
	case "":
		s.note(fmt.Sprintf("its answer to a first 128-byte request is none of the units' (checking anyway): %s", hexWords(got)))
	default:
		s.fatal = fmt.Errorf("answers like %s, not %s: load the %s partial into slot %d", name, c.unit.name, c.unit.name, slot)
		return s
	}

	var jobs []job
	for _, size := range c.sizes {
		if c.respLimit > 0 && responseBytes(c.unit, size) > c.respLimit {
			continue
		}
		for _, framing := range framings {
			cuts := cutsFor(framing, size, c.seg, c.segLimit)
			if cuts == nil {
				continue
			}
			for k := 0; k < c.reqs; k++ {
				jobs = append(jobs, job{size, framing, cuts, k % len(c.unit.shapes)})
			}
		}
	}
	rng.Shuffle(len(jobs), func(a, b int) { jobs[a], jobs[b] = jobs[b], jobs[a] })

	l := &link{addr: c.addr, timeout: c.timeout}
	defer l.drop()
	silent := 0
	for _, j := range jobs {
		r := newRequest(c.unit, slot, j.size, j.framing, j.cuts, c.unit.shapes[j.shape], rng)
		v, want, got, err := c.run(l, r, true)
		s.record(c, tallyKey(j.size, j.framing), r, v, want, got, err)
		if err != nil {
			silent++
		} else {
			silent = 0
		}
		if silent >= maxSilent {
			s.fatal = fmt.Errorf("stopped answering: %d requests in a row failed", maxSilent)
			return s
		}
	}
	return s
}

// concurrent is the second pass: c.conns connections at once on the slot,
// whole requests of the sizes that fit one segment.
func (c *config) concurrent(s *slotReport) {
	var sizes []int
	for _, size := range c.sizes {
		if size <= c.segLimit && (c.respLimit == 0 || responseBytes(c.unit, size) <= c.respLimit) {
			sizes = append(sizes, size)
		}
	}
	if len(sizes) == 0 {
		s.note("no size fits one segment: no concurrent pass")
		return
	}
	var wg sync.WaitGroup
	for k := 0; k < c.conns; k++ {
		wg.Add(1)
		go func(k int) {
			defer wg.Done()
			rng := rand.New(rand.NewSource(c.seed*1000003 + int64(s.slot)*101 + int64(k)))
			l := &link{addr: c.addr, timeout: c.timeout}
			defer l.drop()
			silent := 0
			for n := 0; n < c.concReqs; n++ {
				size := sizes[rng.Intn(len(sizes))]
				sh := c.unit.shapes[rng.Intn(len(c.unit.shapes))]
				r := newRequest(c.unit, s.slot, size, "whole", []int{size}, sh, rng)
				v, want, got, err := c.run(l, r, false)
				s.record(c, "concurrent", r, v, want, got, err)
				if err != nil {
					silent++
				} else {
					silent = 0
				}
				if silent >= maxSilent {
					s.note(fmt.Sprintf("connection %d stopped after %d requests in a row failed", k, maxSilent))
					return
				}
			}
			if l.conn != nil {
				if n := extra(l.conn, finalWait); n > 0 {
					s.note(fmt.Sprintf("connection %d got %d bytes after its last answer", k, n))
				}
			}
		}(k)
	}
	wg.Wait()
}

// report prints a slot's results and says whether every answer was right.
func (c *config) report(s *slotReport) bool {
	fmt.Printf("slot %d: ", s.slot)
	if s.fatal != nil {
		fmt.Printf("FAIL, %v\n", s.fatal)
		for _, f := range s.failures {
			fmt.Print(f)
		}
		return false
	}
	sent, right := 0, 0
	for _, t := range s.tallies {
		sent += t.sent
		right += t.right
	}
	status := "ok"
	if right != sent {
		status = "FAIL"
	}
	fmt.Printf("%s, %d of %d answers right", status, right, sent)
	if c.unit.float && s.words > 0 {
		fmt.Printf("; %d values, %.2f%% bit for bit, at most %d ulp off",
			s.words, 100*float64(s.exact)/float64(s.words), s.maxULP)
	}
	fmt.Println()
	fmt.Printf("  %7s %9s %9s %9s\n", "bytes", "whole", "split", "header")
	for _, size := range c.sizes {
		row := fmt.Sprintf("  %7d", size)
		for _, framing := range framings {
			cell := "-"
			if t := s.tallies[tallyKey(size, framing)]; t != nil {
				cell = fmt.Sprintf("%d/%d", t.right, t.sent)
			}
			row += fmt.Sprintf(" %9s", cell)
		}
		fmt.Println(row)
	}
	if t := s.tallies["concurrent"]; t != nil {
		fmt.Printf("  %d connections at once, whole requests: %d/%d\n", c.conns, t.right, t.sent)
	}
	for _, note := range s.notes {
		fmt.Printf("  note: %s\n", note)
	}
	for _, f := range s.failures {
		fmt.Print(f)
	}
	return right == sent
}

// ---------------------------------------------------------------- main

func parseInts(text, what string) ([]int, error) {
	var out []int
	seen := map[int]bool{}
	for _, field := range strings.Split(text, ",") {
		field = strings.TrimSpace(field)
		if field == "" {
			continue
		}
		value, err := strconv.Atoi(field)
		if err != nil {
			return nil, fmt.Errorf("%s %q: %v", what, field, err)
		}
		if seen[value] {
			return nil, fmt.Errorf("%s %d is listed twice", what, value)
		}
		seen[value] = true
		out = append(out, value)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no %s given", what)
	}
	return out, nil
}

func usage(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(2)
}

func main() {
	addr := flag.String("addr", defaultServerAddress, "design TCP endpoint")
	unitName := flag.String("unit", "", "what the slots hold: top_k, log, norm, pattern_slot or or_slot")
	slotList := flag.String("slots", "0,1,2,3", "comma-separated slots to check; slot N is cell C0N")
	sizeList := flag.String("sizes", "128,192,1024,2048,4096,8192", "comma-separated request sizes in bytes, the 64-byte header included")
	reqs := flag.Int("reqs", 16, "requests of each size in each framing, first pass")
	seg := flag.Int("seg", 1024, "segment bytes for the split and header framings")
	conns := flag.Int("conns", 4, "connections per slot in the second pass, 0 for none")
	concReqs := flag.Int("conc-reqs", 200, "requests per connection in the second pass")
	seed := flag.Int64("seed", 1, "seed of the request data")
	timeout := flag.Duration("timeout", 2*time.Second, "per-request timeout")
	gap := flag.Duration("gap", 200*time.Microsecond, "pause between the segments of a request, so that they are not merged")
	logULPs := flag.Int64("log-ulps", 2, "units in the last place log's answers may be off")
	normULPs := flag.Int64("norm-ulps", 0, "units in the last place norm's answers may be off")
	show := flag.Int("show", 3, "wrong answers to print per slot")
	flag.Parse()
	if flag.NArg() != 0 {
		usage("unexpected arguments: %v", flag.Args())
	}

	units := makeUnits(*logULPs, *normULPs)
	name := strings.ToLower(strings.TrimSpace(*unitName))
	if alias, ok := unitAliases[name]; ok {
		name = alias
	}
	u := units[name]
	if u == nil {
		usage("-unit must be one of %s", strings.Join(unitOrder, ", "))
	}
	slots, err := parseInts(*slotList, "slot")
	if err != nil {
		usage("-slots: %v", err)
	}
	for _, slot := range slots {
		if slot < 0 || slot >= slotCount {
			usage("-slots: slot %d is not one of 0..%d", slot, slotCount-1)
		}
	}
	sizes, err := parseInts(*sizeList, "size")
	if err != nil {
		usage("-sizes: %v", err)
	}
	sort.Ints(sizes)
	for _, size := range sizes {
		if size%lineBytes != 0 || size < 2*lineBytes || size > maxRequestBytes {
			usage("-sizes: %d is not a multiple of 64 from 128 to %d: the header and at least one data line", size, maxRequestBytes)
		}
		if u.name == "norm" && (size-lineBytes)/lineBytes > normMaxDataLines {
			usage("-sizes: %d bytes is %d data lines, and norm holds %d; a longer request never finishes and the slot must be reloaded",
				size, (size-lineBytes)/lineBytes, normMaxDataLines)
		}
	}
	if *seg%lineBytes != 0 || *seg < 2*lineBytes {
		usage("-seg must be a multiple of 64, at least 128")
	}
	if *reqs < 1 || *conns < 0 || *concReqs < 1 || *show < 0 || *logULPs < 0 || *normULPs < 0 {
		usage("-reqs and -conc-reqs must be at least 1; -conns, -show and the ulps not negative")
	}

	mss, iface, mtu, err := probeMSS(*addr, *timeout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "cannot connect to %s: %v\nis the FPGA programmed, and does it answer ping?\n", *addr, err)
		os.Exit(1)
	}
	segLimit := mss / lineBytes * lineBytes
	if segLimit > maxSegmentBytes {
		segLimit = maxSegmentBytes
	}
	if segLimit < 2*lineBytes {
		fmt.Fprintf(os.Stderr, "the TCP MSS to %s is %d bytes, too short for a header and a data line\n", *addr, mss)
		os.Exit(1)
	}
	c := &config{
		addr: *addr, unit: u, units: units, sizes: sizes, reqs: *reqs, seg: *seg, segLimit: segLimit,
		conns: *conns, concReqs: *concReqs, seed: *seed, timeout: *timeout, gap: *gap, show: *show,
	}
	if c.seg > segLimit {
		c.seg = segLimit
	}

	slotNames := make([]string, len(slots))
	for idx, slot := range slots {
		slotNames[idx] = strconv.Itoa(slot)
	}
	fmt.Printf("checkfuncs: %s in slots %s at %s, seed %d\n", u.name, strings.Join(slotNames, ","), *addr, *seed)
	where := ""
	if iface != "" {
		where = fmt.Sprintf(" on %s, MTU %d", iface, mtu)
	}
	fmt.Printf("TCP MSS %d%s: segments of up to %d bytes, split and header framings in %d\n", mss, where, segLimit, c.seg)
	if mss%lineBytes != 0 && mss < maxSegmentBytes {
		fmt.Printf("  %d is not whole lines: should the host's stack merge two writes and cut them at it,\n"+
			"  pkt_receiver refuses the segment and the request goes unanswered\n", mss)
	}
	// The FPGA sends segments of up to 8192 bytes, whatever MSS the host
	// advertises.  When this host's own MTU is what holds the MSS down,
	// longer answers are dropped here.
	if mss < maxSegmentBytes && mtu > 0 && mss+40 >= mtu-40 {
		c.respLimit = mss
		fmt.Printf("  the FPGA answers in segments of up to %d bytes, and with MTU %d this host drops any longer than %d:\n"+
			"  sizes whose answer is longer are left out (raise %s's MTU to 9000 to check them)\n",
			maxSegmentBytes, mtu, mss, iface)
	}
	fmt.Println()

	reports := make([]*slotReport, len(slots))
	var wg sync.WaitGroup
	for idx, slot := range slots {
		wg.Add(1)
		go func(idx, slot int) {
			defer wg.Done()
			reports[idx] = c.checkSlot(slot)
		}(idx, slot)
	}
	wg.Wait()
	if c.conns > 0 {
		for _, s := range reports {
			if s.fatal == nil {
				wg.Add(1)
				go func(s *slotReport) {
					defer wg.Done()
					c.concurrent(s)
				}(s)
			}
		}
		wg.Wait()
	}

	good := 0
	for _, s := range reports {
		if c.report(s) {
			good++
		}
		fmt.Println()
	}
	if good != len(reports) {
		fmt.Printf("FAIL: %s answered wrong, or not at all, in %d of %d slots\n", u.name, len(reports)-good, len(reports))
		os.Exit(1)
	}
	fmt.Printf("ok: %s answered right in every slot checked\n", u.name)
}
