// Command app sends one framed fRAC application request to an accelerator slot
// and prints the response.
//
// It is the counterpart to sw/pr, which talks to the reconfiguration
// controller (workload 0x00ab). This one talks to the accelerator slots.
//
// # Request framing
//
// A request is a 64-byte fRAC header followed by zero or more 64-byte data
// lines. The header's fields are parsed by dispatcher.v; the slot modules
// parse the same line again for their own purposes:
//
//	bytes 0-55   0xff. pkt_logic.v does not require this, but top_k, log and
//	             norm each detect their header line with
//	             `s_axis_tdata[447:0] == {448{1'b1}}`. Without it the header
//	             is consumed as data.
//	bytes 56-59  declared request size, little-endian. For an application
//	             workload this INCLUDES the 64-byte header. (The controller
//	             path is the exception: it excludes it, and dispatcher.v adds
//	             the 64 back.)
//	bytes 60-61  top config. Bits 1:0 are the FIRST and LAST request flags.
//	             top_k reads these same two bytes as its 16-bit result mask,
//	             so the flags alias mask bits 0 and 1 -- see -kmask.
//	bytes 62-63  workload id, which selects the slot.
//
// # Workload to slot
//
// pkt_logic.v routes 0x0001 to C01 and 0x0002 to C02; every other workload
// except the controller's 0x00ab falls through to C00. So 0/1/2 name the three
// slots and anything else lands in slot 0.
//
// # Two transport rules the hardware enforces
//
//  1. pkt_receiver.v drops any TCP segment that is not a multiple of 64 bytes,
//     is shorter than 64, or is longer than 512. Every segment this tool sends
//     obeys that.
//
//  2. The response length announced to the TCP stack is the length of the
//     request's FIRST TCP segment (pkt_logic.v latches the RX metadata of the
//     request's first beat), while pkt_logic.v forwards only the FINAL response
//     beat -- 64 bytes. The two agree only when the first segment is itself 64
//     bytes. So a request carrying data is sent as a 64-byte header segment
//     followed by data segments; -single-segment turns that off, at the cost of
//     promising the stack more response bytes than the design produces.
//
// Because only the last response beat is forwarded, a multi-line request to
// log or norm returns the results for its LAST line only.
package main

import (
	"encoding/binary"
	"encoding/hex"
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
	"time"
)

const (
	defaultServerAddress = "172.24.1.52:2888"

	// One 512-bit AXI-Stream beat.
	requestLineBytes = 64
	// pkt_receiver.v's MAX_PACKET_BYTES.
	maxSegmentBytes = 512

	requestPrefixBytes = 56

	reqFlagFirst  = 0x1
	reqFlagLast   = 0x2
	reqFlagSingle = reqFlagFirst | reqFlagLast

	defaultTopConfig = 0xffff

	// 32-bit words per line.
	valuesPerLine = requestLineBytes / 4

	// Reserved by pkt_logic.v for the reconfiguration controller.
	reconfWorkloadID = 0x00ab
)

// ---------------------------------------------------------------- request

type request struct {
	workload   uint16
	flags      byte
	topConfig  uint16
	dataLines  int
	totalBytes int
	segments   [][]byte
}

func buildHeader(totalSize int, workloadID uint16, flags byte, topConfig uint16) []byte {
	header := make([]byte, requestLineBytes)
	for idx := 0; idx < requestPrefixBytes; idx++ {
		header[idx] = 0xff
	}
	binary.LittleEndian.PutUint32(header[56:60], uint32(totalSize))
	binary.LittleEndian.PutUint16(header[60:62], topConfig)
	header[60] = (header[60] &^ 0x3) | (flags & 0x3)
	binary.LittleEndian.PutUint16(header[62:64], workloadID)
	return header
}

// effectiveTopConfig is what the slot actually reads out of bytes 60-61 once
// the request flags have been written over bits 1:0.
func effectiveTopConfig(topConfig uint16, flags byte) uint16 {
	return (topConfig &^ 0x3) | uint16(flags&0x3)
}

// buildRequest frames a request for workload with payload as its data lines.
//
// With no payload the request is a single 64-byte line and carries FIRST|LAST.
// With payload it is split so the header travels alone in a 64-byte segment,
// which is what keeps the announced response length at 64; the header then
// carries FIRST only, because dispatcher.v treats FIRST|LAST on a segment-final
// header beat as the end of the whole request.
func buildRequest(workload uint16, payload []byte, topConfig uint16, singleSegment bool) (*request, error) {
	if len(payload)%requestLineBytes != 0 {
		return nil, fmt.Errorf("payload must be a whole number of %d-byte lines, got %d", requestLineBytes, len(payload))
	}
	total := requestLineBytes + len(payload)

	req := &request{
		workload:   workload,
		topConfig:  topConfig,
		dataLines:  len(payload) / requestLineBytes,
		totalBytes: total,
	}

	switch {
	case len(payload) == 0:
		req.flags = reqFlagSingle
		req.segments = [][]byte{buildHeader(total, workload, req.flags, topConfig)}

	case singleSegment:
		if total > maxSegmentBytes {
			return nil, fmt.Errorf("-single-segment needs the whole %d-byte request to fit one %d-byte segment", total, maxSegmentBytes)
		}
		req.flags = reqFlagSingle
		seg := append(buildHeader(total, workload, req.flags, topConfig), payload...)
		req.segments = [][]byte{seg}

	default:
		req.flags = reqFlagFirst
		req.segments = [][]byte{buildHeader(total, workload, req.flags, topConfig)}
		for offset := 0; offset < len(payload); offset += maxSegmentBytes {
			end := offset + maxSegmentBytes
			if end > len(payload) {
				end = len(payload)
			}
			req.segments = append(req.segments, payload[offset:end])
		}
	}

	for idx, seg := range req.segments {
		if len(seg)%requestLineBytes != 0 || len(seg) < requestLineBytes || len(seg) > maxSegmentBytes {
			return nil, fmt.Errorf("segment %d is %d bytes; pkt_receiver.v accepts %d..%d in %d-byte steps",
				idx, len(seg), requestLineBytes, maxSegmentBytes, requestLineBytes)
		}
	}
	return req, nil
}

// --------------------------------------------------------------- transport

type exchange struct {
	response  []byte
	writeTime time.Duration
	readTime  time.Duration
}

func writeFull(writer io.Writer, data []byte) error {
	for len(data) > 0 {
		written, err := writer.Write(data)
		if err != nil {
			return err
		}
		if written == 0 {
			return io.ErrShortWrite
		}
		data = data[written:]
	}
	return nil
}

// send writes every segment, pausing between them so the kernel emits each as
// its own TCP segment rather than coalescing them, then reads the single
// 64-byte response.
func send(conn net.Conn, req *request, timeout, gap time.Duration) (*exchange, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, fmt.Errorf("set deadline: %w", err)
	}

	writeStart := time.Now()
	for idx, seg := range req.segments {
		if idx > 0 && gap > 0 {
			time.Sleep(gap)
		}
		if err := writeFull(conn, seg); err != nil {
			return nil, fmt.Errorf("send segment %d: %w", idx, err)
		}
	}
	writeTime := time.Since(writeStart)

	readStart := time.Now()
	response := make([]byte, requestLineBytes)
	if _, err := io.ReadFull(conn, response); err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	return &exchange{response: response, writeTime: writeTime, readTime: time.Since(readStart)}, nil
}

func dial(addr string, timeout time.Duration, recvBuffer int) (net.Conn, error) {
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return nil, err
	}
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		if err := tcpConn.SetNoDelay(true); err != nil {
			conn.Close()
			return nil, fmt.Errorf("set TCP_NODELAY: %w", err)
		}
		if recvBuffer > 0 {
			if err := tcpConn.SetReadBuffer(recvBuffer); err != nil {
				conn.Close()
				return nil, fmt.Errorf("set TCP read buffer: %w", err)
			}
		}
	}
	return conn, nil
}

// ----------------------------------------------------------------- payload

func parseUint(text string, bits int) (uint64, error) {
	text = strings.TrimSpace(text)
	return strconv.ParseUint(strings.TrimPrefix(strings.TrimPrefix(text, "0x"), "0X"), map[bool]int{true: 16, false: 10}[strings.HasPrefix(text, "0x") || strings.HasPrefix(text, "0X")], bits)
}

func padLines(data []byte) []byte {
	if len(data)%requestLineBytes == 0 {
		return data
	}
	out := make([]byte, ((len(data)/requestLineBytes)+1)*requestLineBytes)
	copy(out, data)
	return out
}

func payloadFromFloats(values []float64) []byte {
	out := make([]byte, 0, len(values)*4)
	for _, value := range values {
		var word [4]byte
		binary.LittleEndian.PutUint32(word[:], math.Float32bits(float32(value)))
		out = append(out, word[:]...)
	}
	return padLines(out)
}

func payloadFromUints(values []uint64) []byte {
	out := make([]byte, 0, len(values)*4)
	for _, value := range values {
		var word [4]byte
		binary.LittleEndian.PutUint32(word[:], uint32(value))
		out = append(out, word[:]...)
	}
	return padLines(out)
}

func splitList(text string) []string {
	fields := strings.FieldsFunc(text, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' || r == '\n' })
	out := fields[:0]
	for _, field := range fields {
		if field != "" {
			out = append(out, field)
		}
	}
	return out
}

func buildPayload(floats, ints, file string, lines int, fill string, seed int64) ([]byte, error) {
	set := 0
	for _, text := range []string{floats, ints, file} {
		if text != "" {
			set++
		}
	}
	if lines > 0 {
		set++
	}
	switch {
	case set == 0:
		return nil, nil
	case set > 1:
		return nil, fmt.Errorf("choose one of -floats, -ints, -payload-file, -lines")
	}

	switch {
	case floats != "":
		values := make([]float64, 0, 16)
		for _, field := range splitList(floats) {
			value, err := strconv.ParseFloat(field, 64)
			if err != nil {
				return nil, fmt.Errorf("-floats %q: %w", field, err)
			}
			values = append(values, value)
		}
		if len(values) == 0 {
			return nil, fmt.Errorf("-floats is empty")
		}
		return payloadFromFloats(values), nil

	case ints != "":
		values := make([]uint64, 0, 16)
		for _, field := range splitList(ints) {
			value, err := parseUint(field, 32)
			if err != nil {
				return nil, fmt.Errorf("-ints %q: %w", field, err)
			}
			values = append(values, value)
		}
		if len(values) == 0 {
			return nil, fmt.Errorf("-ints is empty")
		}
		return payloadFromUints(values), nil

	case file != "":
		data, err := os.ReadFile(file)
		if err != nil {
			return nil, fmt.Errorf("read -payload-file: %w", err)
		}
		if len(data) == 0 {
			return nil, fmt.Errorf("-payload-file %s is empty", file)
		}
		return padLines(data), nil
	}

	count := lines * valuesPerLine
	values := make([]float64, count)
	switch fill {
	case "ramp":
		// Inside (0, 1): log's ln(x/(1-x)) needs it and norm is happiest there.
		for idx := range values {
			values[idx] = float64(idx%valuesPerLine+1) / float64(valuesPerLine+1)
		}
	case "random":
		rng := rand.New(rand.NewSource(seed))
		for idx := range values {
			values[idx] = 0.01 + 0.98*rng.Float64()
		}
	case "zeros":
		// leave at 0.0
	default:
		value, err := strconv.ParseFloat(fill, 64)
		if err != nil {
			return nil, fmt.Errorf("-fill must be ramp, random, zeros or a float, got %q", fill)
		}
		for idx := range values {
			values[idx] = value
		}
	}
	return payloadFromFloats(values), nil
}

// ----------------------------------------------------------------- decode

func words(data []byte) []uint32 {
	out := make([]uint32, len(data)/4)
	for idx := range out {
		out[idx] = binary.LittleEndian.Uint32(data[idx*4:])
	}
	return out
}

func constantByte(data []byte) (byte, bool) {
	if len(data) == 0 {
		return 0, false
	}
	for _, value := range data[1:] {
		if value != data[0] {
			return 0, false
		}
	}
	return data[0], true
}

func printResponse(response []byte, decode string) {
	if value, ok := constantByte(response); ok {
		fmt.Printf("  all %d bytes are 0x%02x\n", len(response), value)
	}
	fmt.Print(indent(hex.Dump(response), "  "))

	show := decode
	if decode == "auto" {
		if _, ok := constantByte(response); ok {
			return
		}
		show = "both"
	}
	if show == "none" {
		return
	}

	raw := words(response)
	for idx, word := range raw {
		switch show {
		case "u32":
			fmt.Printf("  [%2d] 0x%08x  %d\n", idx, word, word)
		case "f32":
			fmt.Printf("  [%2d] 0x%08x  %g\n", idx, word, math.Float32frombits(word))
		default:
			fmt.Printf("  [%2d] 0x%08x  u32=%-12d f32=%g\n", idx, word, word, math.Float32frombits(word))
		}
	}
}

func indent(text, prefix string) string {
	lines := strings.Split(strings.TrimRight(text, "\n"), "\n")
	for idx := range lines {
		lines[idx] = prefix + lines[idx]
	}
	return strings.Join(lines, "\n") + "\n"
}

// --------------------------------------------------------------- identify

// identifyInputs is one data line of values in (0, 1), which every slot module
// answers and each one answers differently.
func identifyInputs() []float64 {
	values := make([]float64, valuesPerLine)
	for idx := range values {
		values[idx] = 0.05 * float64(idx+1)
	}
	return values
}

type candidate struct {
	name     string
	expected []uint32
	// exact says the expectation is a bit pattern rather than a float result.
	exact bool
}

func identifyCandidates(inputs []float64, kmask uint16) []candidate {
	ones := make([]uint32, valuesPerLine)
	pattern := make([]uint32, valuesPerLine)
	for idx := range ones {
		ones[idx] = 0xffffffff
		pattern[idx] = 0x01010101
	}

	sorted := make([]uint32, len(inputs))
	for idx, value := range inputs {
		sorted[idx] = math.Float32bits(float32(value))
	}
	sort.Slice(sorted, func(a, b int) bool { return sorted[a] > sorted[b] })
	for idx := range sorted {
		if kmask&(1<<uint(idx)) == 0 {
			sorted[idx] = 0
		}
	}

	logOut := make([]uint32, len(inputs))
	for idx, x := range inputs {
		logOut[idx] = math.Float32bits(float32(math.Log(x / (1 - x))))
	}

	min, max := inputs[0], inputs[0]
	for _, x := range inputs {
		if x < min {
			min = x
		}
		if x > max {
			max = x
		}
	}
	normOut := make([]uint32, len(inputs))
	for idx, x := range inputs {
		normOut[idx] = math.Float32bits(float32((x - min) / (max - min)))
	}

	return []candidate{
		{name: "or_slot", expected: ones, exact: true},
		{name: "pattern_slot", expected: pattern, exact: true},
		{name: "top_k", expected: sorted, exact: true},
		{name: "log", expected: logOut},
		{name: "norm", expected: normOut},
	}
}

// score is the number of words that match, with floats compared loosely
// because the cores round differently from the host.
func score(got, want []uint32, exact bool) int {
	matched := 0
	for idx := range want {
		if idx >= len(got) {
			break
		}
		if exact {
			if got[idx] == want[idx] {
				matched++
			}
			continue
		}
		a := float64(math.Float32frombits(got[idx]))
		b := float64(math.Float32frombits(want[idx]))
		switch {
		case math.IsNaN(a) || math.IsNaN(b):
		case a == b:
			matched++
		case math.Abs(a-b) <= 1e-3*math.Max(1, math.Abs(b)):
			matched++
		}
	}
	return matched
}

func identify(addr string, slots []uint16, timeout, gap time.Duration, recvBuffer int, kmask uint16, decode string) error {
	inputs := identifyInputs()
	payload := payloadFromFloats(inputs)

	fmt.Printf("identify: one header segment + one data line of %d values in (0,1)\n", len(inputs))
	effective := effectiveTopConfig(kmask, reqFlagFirst)
	if effective != kmask {
		fmt.Printf("note: the FIRST/LAST flags overwrite bits 1:0 of bytes 60-61, so top_k sees mask 0x%04x, not 0x%04x\n",
			effective, kmask)
	}
	fmt.Println()

	for _, workload := range slots {
		req, err := buildRequest(workload, payload, kmask, false)
		if err != nil {
			return err
		}

		conn, err := dial(addr, timeout, recvBuffer)
		if err != nil {
			return fmt.Errorf("connect %s: %w", addr, err)
		}
		result, err := send(conn, req, timeout, gap)
		conn.Close()

		fmt.Printf("workload 0x%04x (slot %d):\n", workload, workload)
		if err != nil {
			fmt.Printf("  no response: %v\n", err)
			fmt.Println("  log and norm answer this probe, so a timeout means an empty or stalled cell.")
			fmt.Println()
			continue
		}

		got := words(result.response)
		best, bestScore := "", -1
		for _, cand := range identifyCandidates(inputs, effective) {
			if matched := score(got, cand.expected, cand.exact); matched > bestScore {
				best, bestScore = cand.name, matched
			}
		}
		verdict := fmt.Sprintf("%s (%d/%d words)", best, bestScore, valuesPerLine)
		if bestScore < valuesPerLine/2 {
			verdict = fmt.Sprintf("unrecognised; closest is %s (%d/%d words)", best, bestScore, valuesPerLine)
		}
		fmt.Printf("  %s   latency %s\n", verdict, result.writeTime+result.readTime)
		printResponse(result.response, decode)
		fmt.Println()
	}
	return nil
}

// ------------------------------------------------------------------- main

func main() {
	addr := flag.String("addr", defaultServerAddress, "TCP server address")
	workload := flag.String("workload", "0", "workload id; 0/1/2 select slots C00/C01/C02 (decimal or 0x hex)")
	timeout := flag.Duration("timeout", 5*time.Second, "dial/read/write timeout")
	gap := flag.Duration("segment-gap", 2*time.Millisecond, "pause between TCP segments so the kernel does not coalesce them")
	recvBuffer := flag.Int("recv-buffer", 2048, "TCP receive buffer size in bytes, 0 to leave the default")
	count := flag.Int("count", 1, "send the request this many times on one connection")
	decode := flag.String("decode", "auto", "response decode: auto, none, u32, f32, both")
	kmask := flag.String("kmask", "0xffff", "bytes 60-61 of the header; top_k reads them as its 16-bit result mask")
	singleSegment := flag.Bool("single-segment", false, "send header and data in one TCP segment (promises the TCP stack more response bytes than the design returns)")
	dumpRequest := flag.Bool("dump-request", false, "hex dump every request segment before sending")
	doIdentify := flag.Bool("identify", false, "probe slots 0..2 and report which accelerator answers in each")
	identifySlots := flag.String("identify-slots", "0,1,2", "slots to probe in -identify mode")

	floats := flag.String("floats", "", "comma-separated float32 data values")
	ints := flag.String("ints", "", "comma-separated uint32 data values (decimal or 0x hex)")
	payloadFile := flag.String("payload-file", "", "raw data lines read from this file")
	lines := flag.Int("lines", 0, "generate this many 64-byte data lines")
	fill := flag.String("fill", "ramp", "how -lines is filled: ramp, random, zeros, or a constant float")
	seed := flag.Int64("seed", 1, "seed for -fill random")

	flag.Parse()

	maskValue, err := parseUint(*kmask, 16)
	if err != nil {
		fmt.Fprintf(os.Stderr, "-kmask: %v\n", err)
		os.Exit(2)
	}

	if *doIdentify {
		var slots []uint16
		for _, field := range splitList(*identifySlots) {
			value, err := parseUint(field, 16)
			if err != nil {
				fmt.Fprintf(os.Stderr, "-identify-slots %q: %v\n", field, err)
				os.Exit(2)
			}
			slots = append(slots, uint16(value))
		}
		if err := identify(*addr, slots, *timeout, *gap, *recvBuffer, uint16(maskValue), *decode); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}

	workloadValue, err := parseUint(*workload, 16)
	if err != nil {
		fmt.Fprintf(os.Stderr, "-workload: %v\n", err)
		os.Exit(2)
	}
	if workloadValue == reconfWorkloadID {
		fmt.Fprintf(os.Stderr, "workload 0x%04x is the reconfiguration controller; use sw/pr for that\n", reconfWorkloadID)
		os.Exit(2)
	}
	if *count < 1 {
		fmt.Fprintf(os.Stderr, "-count must be at least 1, got %d\n", *count)
		os.Exit(2)
	}

	payload, err := buildPayload(*floats, *ints, *payloadFile, *lines, *fill, *seed)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	req, err := buildRequest(uint16(workloadValue), payload, uint16(maskValue), *singleSegment)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	fmt.Printf("request: workload=0x%04x total=%dB header=64B data=%d line(s) segments=%d flags=0x%x\n",
		req.workload, req.totalBytes, req.dataLines, len(req.segments), req.flags)
	if effective := effectiveTopConfig(req.topConfig, req.flags); effective != req.topConfig {
		fmt.Printf("note: the request flags overwrite bits 1:0 of bytes 60-61, so top_k sees mask 0x%04x, not 0x%04x\n",
			effective, req.topConfig)
	}
	if req.dataLines == 0 {
		fmt.Println("note: a header-only request returns nothing from log or norm; give them at least one data line")
	}
	if *singleSegment && req.dataLines > 0 {
		fmt.Printf("note: -single-segment announces a %d-byte response but the design returns 64; the connection will desync\n", req.totalBytes)
	}
	if *dumpRequest {
		for idx, seg := range req.segments {
			fmt.Printf("segment %d (%dB):\n%s", idx, len(seg), indent(hex.Dump(seg), "  "))
		}
	}

	conn, err := dial(*addr, *timeout, *recvBuffer)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect %s: %v\n", *addr, err)
		os.Exit(1)
	}
	defer conn.Close()

	latencies := make([]time.Duration, 0, *count)
	for iteration := 0; iteration < *count; iteration++ {
		result, err := send(conn, req, *timeout, *gap)
		if err != nil {
			fmt.Fprintf(os.Stderr, "request %d: %v\n", iteration, err)
			os.Exit(1)
		}
		latency := result.writeTime + result.readTime
		latencies = append(latencies, latency)

		if *count == 1 {
			fmt.Printf("response: %dB  write=%s read=%s\n", len(result.response), result.writeTime, result.readTime)
			printResponse(result.response, *decode)
		} else if iteration == *count-1 {
			fmt.Printf("last response: %dB\n", len(result.response))
			printResponse(result.response, *decode)
		}
	}

	if *count > 1 {
		sorted := append([]time.Duration(nil), latencies...)
		sort.Slice(sorted, func(a, b int) bool { return sorted[a] < sorted[b] })
		var total time.Duration
		for _, value := range sorted {
			total += value
		}
		fmt.Printf("%d requests: min=%s p50=%s max=%s avg=%s\n",
			len(sorted), sorted[0], sorted[len(sorted)/2], sorted[len(sorted)-1], total/time.Duration(len(sorted)))
	}
}
