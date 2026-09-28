// Command patprobe sends a deterministic bit pattern to an accelerator slot and
// reports what answered. It is the companion to query.go, which sends floats so
// that the arithmetic cores (top_k, log, norm) can be recognised by their
// results; this one sends a fixed 32-bit word instead, which is what you want
// when the question is simply "did the slot change?".
//
// 0xaaaaaaaa is the default for a reason: 0xAA is 10101010, so a bit reversal
// or an inversion anywhere in the path comes back as 0x55 and is impossible to
// miss. -counter sends an incrementing word instead, which additionally proves
// nothing reordered the data.
//
// Request framing is identical to query.go (dispatcher.v parses it):
//
//	bytes 0-55   0xff filler
//	bytes 56-59  declared size, little-endian, INCLUDING the 64-byte header
//	bytes 60-61  top config; bits 1:0 are the FIRST and LAST request flags
//	bytes 62-63  workload id, which selects the slot
//
// The slot answers one 64-byte line per request beat, so a header+data request
// comes back as two lines: the echoed header, then the slot's answer to the
// data. Reading only the first would show the header and leave the rest queued
// to desync the next request, so every line is read.
package main

import (
	"encoding/binary"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultServerAddress = "172.24.1.52:2888"

	// One 512-bit AXI-Stream beat.
	requestLineBytes = 64
	// pkt_receiver.v's MAX_PACKET_BYTES on the older builds; newer ones accept
	// more, but staying at 512 works everywhere.
	maxSegmentBytes    = 512
	requestPrefixBytes = 56
	wordsPerLine       = requestLineBytes / 4

	reqFlagFirst = 0x1
	reqFlagLast  = 0x2

	defaultTopConfig = 0xffff

	// Reserved by pkt_logic.v for the reconfiguration controller.
	reconfWorkloadID = 0x00ab

	// How long to wait for each response line after the first.
	trailingLineWait = 300 * time.Millisecond
)

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

// patternWords is the data the slot will see, as little-endian 32-bit words.
func patternWords(word uint32, counter bool, lines int) []uint32 {
	out := make([]uint32, wordsPerLine*lines)
	for idx := range out {
		if counter {
			out[idx] = word + uint32(idx)
		} else {
			out[idx] = word
		}
	}
	return out
}

func payloadFromWords(values []uint32) []byte {
	out := make([]byte, len(values)*4)
	for idx, value := range values {
		binary.LittleEndian.PutUint32(out[idx*4:], value)
	}
	return out
}

func words(data []byte) []uint32 {
	out := make([]uint32, len(data)/4)
	for idx := range out {
		out[idx] = binary.LittleEndian.Uint32(data[idx*4:])
	}
	return out
}

// lastLine is the final 64-byte line: the slot's answer to the data line, after
// any echoed header.
func lastLine(data []byte) []byte {
	if len(data) <= requestLineBytes {
		return data
	}
	return data[len(data)-requestLineBytes:]
}

// buildSegments frames the request. The header travels in a segment of its own
// so the response length the TCP stack is told stays 64; with payload it
// carries FIRST only, because dispatcher.v reads FIRST|LAST on a segment-final
// header beat as the end of the whole request.
func buildSegments(workload uint16, payload []byte, topConfig uint16) ([][]byte, int, byte) {
	total := requestLineBytes + len(payload)
	if len(payload) == 0 {
		flags := byte(reqFlagFirst | reqFlagLast)
		return [][]byte{buildHeader(total, workload, flags, topConfig)}, total, flags
	}
	flags := byte(reqFlagFirst)
	segments := [][]byte{buildHeader(total, workload, flags, topConfig)}
	for offset := 0; offset < len(payload); offset += maxSegmentBytes {
		end := offset + maxSegmentBytes
		if end > len(payload) {
			end = len(payload)
		}
		segments = append(segments, payload[offset:end])
	}
	return segments, total, flags
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

// exchange writes every segment, then reads the whole response: the first line
// on the full timeout because it must arrive, any further lines on a short one,
// stopping at the first gap so a design that forwards a single beat still works.
func exchange(conn net.Conn, segments [][]byte, totalBytes int, timeout, gap time.Duration) ([]byte, time.Duration, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, 0, err
	}
	start := time.Now()
	for idx, seg := range segments {
		if idx > 0 && gap > 0 {
			time.Sleep(gap)
		}
		if err := writeFull(conn, seg); err != nil {
			return nil, 0, fmt.Errorf("send segment %d: %w", idx, err)
		}
	}

	response := make([]byte, requestLineBytes)
	if _, err := io.ReadFull(conn, response); err != nil {
		return nil, 0, fmt.Errorf("read response: %w", err)
	}
	maxLines := totalBytes / requestLineBytes
	if maxLines < 1 {
		maxLines = 1
	}
	for len(response)/requestLineBytes < maxLines {
		if err := conn.SetReadDeadline(time.Now().Add(trailingLineWait)); err != nil {
			break
		}
		line := make([]byte, requestLineBytes)
		if _, err := io.ReadFull(conn, line); err != nil {
			break
		}
		response = append(response, line...)
	}
	_ = conn.SetReadDeadline(time.Time{})
	return response, time.Since(start), nil
}

func matching(got, want []uint32) int {
	n := 0
	for idx := range want {
		if idx < len(got) && got[idx] == want[idx] {
			n++
		}
	}
	return n
}

// classify names the RM from the slot's answer to the data line. sent is the
// last line of what we transmitted, so the echo expectation is exact.
func classify(sent, got []uint32) (string, int) {
	ones := make([]uint32, len(sent))
	fill01 := make([]uint32, len(sent))
	for idx := range ones {
		ones[idx] = 0xffffffff
		fill01[idx] = 0x01010101
	}
	// The 8-bit slot lineage (4514 and the ohif builds) puts ONE byte of slot
	// output in the low byte of the line and zeroes the rest -- pkt_logic builds
	// the response as {tlast, 504'd0, slot_byte}. So or_slot reads ff 00 00 ...
	// and pattern_slot reads 01 00 00 ..., regardless of what was sent.
	narrowFF := make([]uint32, len(sent))
	narrow01 := make([]uint32, len(sent))
	narrowFF[0] = 0x000000ff
	narrow01[0] = 0x00000001

	type cand struct {
		name string
		want []uint32
	}
	best, bestScore := "", -1
	for _, c := range []cand{
		{"or_slot (payload | all-ones, wide line)", ones},
		{"echo_slot (data returned unchanged)", sent},
		{"pattern_slot (0x01 fill, wide line)", fill01},
		{"or_slot (ff 00 00 .., 8-bit line)", narrowFF},
		{"pattern_slot (01 00 00 .., 8-bit line)", narrow01},
	} {
		if n := matching(got, c.want); n > bestScore {
			best, bestScore = c.name, n
		}
	}
	return best, bestScore
}

func parseUint(text string, bits int) (uint64, error) {
	text = strings.TrimSpace(text)
	base := 10
	if strings.HasPrefix(text, "0x") || strings.HasPrefix(text, "0X") {
		text, base = text[2:], 16
	}
	return strconv.ParseUint(text, base, bits)
}

func main() {
	addr := flag.String("addr", defaultServerAddress, "design TCP endpoint")
	slotList := flag.String("slots", "0,1", "comma-separated workload ids to probe; workload N selects slot N")
	wordText := flag.String("word", "0xaaaaaaaa", "32-bit word to fill the data line with (decimal or 0x hex)")
	counter := flag.Bool("counter", false, "send word, word+1, word+2 ... instead of a constant, to prove ordering")
	lines := flag.Int("lines", 1, "data lines to send after the header")
	timeout := flag.Duration("timeout", 10*time.Second, "per-request timeout")
	gap := flag.Duration("gap", 200*time.Microsecond, "pause between TCP segments so they are not coalesced")
	dump := flag.Bool("dump", true, "hex dump each response")
	flag.Parse()

	wordValue, err := parseUint(*wordText, 32)
	if err != nil {
		fmt.Fprintf(os.Stderr, "-word: %v\n", err)
		os.Exit(2)
	}
	if *lines < 1 {
		fmt.Fprintln(os.Stderr, "-lines must be at least 1")
		os.Exit(2)
	}

	var slots []uint16
	for _, field := range strings.Split(*slotList, ",") {
		if strings.TrimSpace(field) == "" {
			continue
		}
		value, err := parseUint(field, 16)
		if err != nil {
			fmt.Fprintf(os.Stderr, "-slots %q: %v\n", field, err)
			os.Exit(2)
		}
		if value == reconfWorkloadID {
			fmt.Fprintf(os.Stderr, "workload 0x%04x is the reconfiguration controller, not a slot\n", reconfWorkloadID)
			os.Exit(2)
		}
		slots = append(slots, uint16(value))
	}
	if len(slots) == 0 {
		fmt.Fprintln(os.Stderr, "-slots selected nothing")
		os.Exit(2)
	}

	sent := patternWords(uint32(wordValue), *counter, *lines)
	payload := payloadFromWords(sent)
	sentLast := sent[len(sent)-wordsPerLine:]

	shape := fmt.Sprintf("0x%08x", uint32(wordValue))
	if *counter {
		shape = fmt.Sprintf("0x%08x, incrementing", uint32(wordValue))
	}
	fmt.Printf("patprobe: header segment + %d data line(s) of %s\n", *lines, shape)
	fmt.Printf("expect or_slot to answer all 0xff whatever it is sent, and an echo RM to return it unchanged\n\n")

	failures := 0
	for _, workload := range slots {
		segments, totalBytes, _ := buildSegments(workload, payload, defaultTopConfig)

		conn, err := net.DialTimeout("tcp", *addr, *timeout)
		if err != nil {
			fmt.Printf("workload 0x%04x (slot %d):\n  connect failed: %v\n\n", workload, workload, err)
			failures++
			continue
		}
		response, elapsed, err := exchange(conn, segments, totalBytes, *timeout, *gap)
		conn.Close()

		fmt.Printf("workload 0x%04x (slot %d):\n", workload, workload)
		if err != nil {
			fmt.Printf("  no response: %v\n", err)
			fmt.Printf("  the first request after a flash or a long idle often times out; try again\n\n")
			failures++
			continue
		}

		got := words(lastLine(response))
		name, matched := classify(sentLast, got)
		verdict := fmt.Sprintf("%s  %d/%d words", name, matched, wordsPerLine)
		if matched < wordsPerLine {
			verdict = fmt.Sprintf("unrecognised; closest is %s (%d/%d words)", name, matched, wordsPerLine)
		}
		fmt.Printf("  %s   %dB in %s\n", verdict, len(response), elapsed)
		if *dump {
			for _, line := range strings.Split(strings.TrimRight(hex.Dump(response), "\n"), "\n") {
				fmt.Printf("  %s\n", line)
			}
		}
		fmt.Println()
	}
	if failures > 0 {
		os.Exit(1)
	}
}
