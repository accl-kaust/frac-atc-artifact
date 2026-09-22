// Command swap proves (or disproves) that network partial reconfiguration
// actually changes the fabric, by alternating two reconfigurable modules in
// one PR slot and probing the slot's behaviour after every step.
//
// It exists because QUERY_STATUS cannot detect a failed reconfiguration:
// reconfctrl samples ICAPE3's PRDONE while reconf_active is set, and that
// flag rises when the command is accepted -- before a single word has been
// streamed -- so it latches PRDONE's idle-high power-up state. ERR_OK and
// prdone_seen=1 therefore appear whether or not the fabric changed. The only
// trustworthy signal is behavioural: or_slot answers a header-only probe
// with 0xff in byte 0, pattern_slot with 0x01. This tool automates that A/B
// experiment and fails loudly when the response does not track the image
// that was just programmed.
//
// Both partials and the full bitstream on the card must come from the SAME
// build. A partial from any other static image programs "successfully" and
// changes nothing. Bitstream sets that ship only or_slot partials cannot
// show a swap at all: the full image boots with or_slot in every slot, so
// or over or is invisible by construction.
//
// Typical run, after JTAG-programming the matching full offrac.bit:
//
//	go run main.go -slot 0 \
//	  -or c00_bbx_inst_or_slot_part.bin \
//	  -pattern c00_bbx_inst_pattern_slot_part.bin
//
// Both images are staged in HBM once, at disjoint addresses; each phase then
// issues one RECONF_ICAP and one probe. Only or_slot and pattern_slot are
// probe-safe targets: log and norm do not answer a header-only request, so
// a swap involving them would block on the probe (use sw/app for those).
package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
)

const (
	defaultServerAddress = "172.24.1.52:2888"
	requestLineBytes     = 64
	requestPrefixBytes   = 56
	defaultTopConfig     = 0xffff
	reconfWorkloadID     = 0x00ab
	reqFlagFirst         = 0x1
	reqFlagLast          = 0x2
	reqFlagSingle        = reqFlagFirst | reqFlagLast

	opWriteHBM   = 1
	opReadHBM    = 2
	opReconfICAP = 3
	opQueryICAP  = 4

	// READ_HBM returns raw data, zero-padded to a line, and reconfctrl rejects
	// a larger size with ERR_SIZE.
	maxReadBytes = 64

	slotCount = 3

	errOK = 0

	// Byte 0 of a header-only probe response, per module.
	orSlotByte      = 0xff
	patternSlotByte = 0x01
)

func buildHeader(totalSize int, workloadID uint16, requestFlags byte) []byte {
	header := make([]byte, requestLineBytes)
	for idx := 0; idx < requestPrefixBytes; idx++ {
		header[idx] = 0xff
	}
	binary.LittleEndian.PutUint32(header[56:60], uint32(totalSize))
	binary.LittleEndian.PutUint16(header[60:62], defaultTopConfig)
	header[60] = (header[60] &^ 0x3) | (requestFlags & 0x3)
	binary.LittleEndian.PutUint16(header[62:64], workloadID)
	return header
}

func buildWorkloadRequest(workloadID uint16) []byte {
	return buildHeader(requestLineBytes, workloadID, reqFlagSingle)
}

func buildReconfCommand(opcode byte, slotID byte, hbmAddr uint64, size uint64) []byte {
	cmd := make([]byte, requestLineBytes)
	cmd[0] = opcode
	cmd[1] = slotID
	binary.LittleEndian.PutUint64(cmd[8:16], hbmAddr)
	binary.LittleEndian.PutUint64(cmd[16:24], size)
	return cmd
}

func buildReconfRequest(opcode byte, slotID byte, hbmAddr uint64, size uint64, payload []byte) []byte {
	totalSize := requestLineBytes + len(payload)
	req := make([]byte, 0, totalSize)
	req = append(req, buildHeader(totalSize, reconfWorkloadID, reqFlagSingle)...)
	req = append(req, buildReconfCommand(opcode, slotID, hbmAddr, size)...)
	req = append(req, payload...)
	return req
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

func sendAndReadStatus(conn net.Conn, timeout time.Duration, name string, request []byte) ([]byte, time.Duration, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, 0, fmt.Errorf("set deadline for %s: %w", name, err)
	}

	startedAt := time.Now()
	if err := writeFull(conn, request); err != nil {
		return nil, 0, fmt.Errorf("send %s request: %w", name, err)
	}
	response := make([]byte, requestLineBytes)
	if _, err := io.ReadFull(conn, response); err != nil {
		return nil, 0, fmt.Errorf("read %s response: %w", name, err)
	}
	return response, time.Since(startedAt), nil
}

func statusOK(response []byte) bool {
	return len(response) == requestLineBytes && response[0] == errOK && bytes.Equal(response[1:], make([]byte, requestLineBytes-1))
}

func responseCodeOK(response []byte) bool {
	return len(response) == requestLineBytes && response[0] == errOK
}

func roundUp(value, align int) int {
	if align <= 0 {
		return value
	}
	rem := value % align
	if rem == 0 {
		return value
	}
	return value + align - rem
}

func padCopy(data []byte, size int) []byte {
	out := make([]byte, size)
	copy(out, data)
	return out
}

var errorNames = map[byte]string{
	0: "ERR_OK",
	1: "ERR_OPCODE",
	2: "ERR_ALIGN",
	3: "ERR_SIZE",
	4: "ERR_ADDR",
	5: "ERR_AXI_BRESP",
	6: "ERR_AXI_RRESP",
	7: "ERR_RLAST",
	8: "ERR_SLOT",
	9: "ERR_ICAP",
}

func errorName(code byte) string {
	if name, ok := errorNames[code]; ok {
		return name
	}
	return fmt.Sprintf("unknown(0x%02x)", code)
}

// printQueryStatus decodes the structured QUERY_STATUS response. It is
// informational only: prdone_seen and last_error report command acceptance,
// not fabric change (see the package comment). last_cycles is the one field
// worth reading -- a value near size/4 means the controller really streamed
// the image out of HBM.
func printQueryStatus(response []byte) {
	fmt.Printf("  query_result   %s\n", errorName(response[0]))
	fmt.Printf("  reconf_active  %d\n", response[1])
	fmt.Printf("  last_slot_id   %d\n", response[2])
	fmt.Printf("  last_error     %s\n", errorName(response[3]))
	fmt.Printf("  icap_avail     %d\n", response[4])
	fmt.Printf("  prdone_seen    %d\n", response[5])
	fmt.Printf("  prerror_seen   %d\n", response[6])
	fmt.Printf("  last_cycles    %d\n", binary.LittleEndian.Uint64(response[8:16]))
	fmt.Printf("  active_cycles  %d\n", binary.LittleEndian.Uint64(response[16:24]))
}

func uploadBitstream(conn net.Conn, timeout time.Duration, hbmAddr uint64, prData []byte, chunkSize int, slotID byte, label string) error {
	for offset := 0; offset < len(prData); {
		end := offset + chunkSize
		if end > len(prData) {
			end = len(prData)
		}

		chunk := prData[offset:end]
		writePayload := chunk
		if len(writePayload)%requestLineBytes != 0 {
			writePayload = padCopy(writePayload, roundUp(len(writePayload), requestLineBytes))
		}

		addr := hbmAddr + uint64(offset)
		req := buildReconfRequest(opWriteHBM, slotID, addr, uint64(len(chunk)), writePayload)
		response, _, err := sendAndReadStatus(conn, timeout, fmt.Sprintf("%s WRITE_HBM[%d]", label, offset/chunkSize), req)
		if err != nil {
			return err
		}
		if !statusOK(response) {
			return fmt.Errorf("%s WRITE_HBM status not OK at offset=%d hbm_addr=0x%x:\n%s", label, offset, addr, hex.Dump(response))
		}
		offset = end
	}
	return nil
}

func readHBM(conn net.Conn, timeout time.Duration, hbmAddr uint64, size int) ([]byte, error) {
	out := make([]byte, 0, size)
	for offset := 0; offset < size; offset += maxReadBytes {
		want := size - offset
		if want > maxReadBytes {
			want = maxReadBytes
		}
		addr := hbmAddr + uint64(offset)
		req := buildReconfRequest(opReadHBM, 0, addr, uint64(want), nil)
		response, _, err := sendAndReadStatus(conn, timeout, fmt.Sprintf("READ_HBM[%d]", offset/maxReadBytes), req)
		if err != nil {
			return out, err
		}
		out = append(out, response[:want]...)
	}
	return out, nil
}

func verifyStaged(conn net.Conn, timeout time.Duration, hbmAddr uint64, prData []byte, label string) error {
	startedAt := time.Now()
	readBack, err := readHBM(conn, timeout, hbmAddr, len(prData))
	if err != nil {
		return err
	}
	for idx := range readBack {
		if readBack[idx] != prData[idx] {
			return fmt.Errorf("%s: HBM mismatch at byte %d (0x%x), hbm_addr=0x%x", label, idx, idx, hbmAddr+uint64(idx))
		}
	}
	fmt.Printf("%s: verified %dB in HBM (%s)\n", label, len(prData), time.Since(startedAt))
	return nil
}

func runReconfig(conn net.Conn, timeout time.Duration, hbmAddr uint64, prSize int, slotID byte, label string) error {
	req := buildReconfRequest(opReconfICAP, slotID, hbmAddr, uint64(prSize), nil)
	response, latency, err := sendAndReadStatus(conn, timeout, label+" RECONF_ICAP", req)
	if err != nil {
		return err
	}
	if !statusOK(response) {
		return fmt.Errorf("%s RECONF_ICAP status not OK:\n%s", label, hex.Dump(response))
	}
	fmt.Printf("%s: RECONF_ICAP accepted slot=%d hbm_addr=0x%x size=%dB latency=%s\n", label, slotID, hbmAddr, prSize, latency)
	return nil
}

func queryStatus(conn net.Conn, timeout time.Duration, slotID byte) error {
	req := buildReconfRequest(opQueryICAP, slotID, 0, 0, nil)
	response, _, err := sendAndReadStatus(conn, timeout, "QUERY_ICAP_STATUS", req)
	if err != nil {
		return err
	}
	if !responseCodeOK(response) {
		return fmt.Errorf("QUERY_ICAP_STATUS status not OK:\n%s", hex.Dump(response))
	}
	printQueryStatus(response)
	return nil
}

func probeSlot(conn net.Conn, timeout time.Duration, workloadID uint16) ([]byte, time.Duration, error) {
	return sendAndReadStatus(conn, timeout, fmt.Sprintf("workload 0x%04x probe", workloadID), buildWorkloadRequest(workloadID))
}

func classify(response []byte) string {
	switch response[0] {
	case orSlotByte:
		return "or_slot"
	case patternSlotByte:
		return "pattern_slot"
	default:
		return fmt.Sprintf("unknown(0x%02x)", response[0])
	}
}

type image struct {
	name   string
	expect byte
	data   []byte
	addr   uint64
}

func loadImage(name, path string, expect byte) (*image, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s bitstream %s: %w", name, path, err)
	}
	if len(data) == 0 {
		return nil, fmt.Errorf("%s bitstream %s is empty", name, path)
	}
	return &image{name: name, expect: expect, data: padCopy(data, roundUp(len(data), 4))}, nil
}

func main() {
	addr := flag.String("addr", defaultServerAddress, "TCP server address")
	orPath := flag.String("or", "", "or_slot partial bitstream (.bin, ICAP format)")
	patternPath := flag.String("pattern", "", "pattern_slot partial bitstream (.bin, ICAP format)")
	slot := flag.Int("slot", 0, fmt.Sprintf("slot to swap, 0..%d (slot N is cell C0N, probed as workload N)", slotCount-1))
	hbmAddr := flag.Uint64("hbm-addr", 0x4000, "32-byte-aligned HBM byte address; the or image is staged here, pattern above it")
	chunkSize := flag.Int("chunk-size", 256, "raw bitstream bytes per HBM write request, 64-byte multiple in 64..256")
	timeout := flag.Duration("timeout", 10*time.Second, "dial/read/write timeout")
	recvBuffer := flag.Int("recv-buffer", 2048, "TCP receive buffer size in bytes")
	settle := flag.Duration("settle", 200*time.Millisecond, "wait after each RECONF_ICAP before probing")
	cycles := flag.Int("cycles", 1, "pattern/or swap cycles to run")
	query := flag.Bool("query-status", true, "print QUERY_ICAP_STATUS after each reconfiguration (informational)")
	verify := flag.Bool("verify", false, "read both staged images back from HBM before swapping")
	dump := flag.Bool("dump", false, "hex dump every probe response")
	seq := flag.String("seq", "", "explicit program order, comma-separated or|pattern tokens (e.g. or,pattern,or); overrides -cycles pattern/or alternation. Use it to program a partial as the SECOND-or-later PR, which the default order never does")
	flag.Parse()

	if *orPath == "" || *patternPath == "" {
		fmt.Fprintf(os.Stderr, "usage: %s -or OR_PART.bin -pattern PATTERN_PART.bin [flags]\n", os.Args[0])
		os.Exit(2)
	}
	if *slot < 0 || *slot >= slotCount {
		fmt.Fprintf(os.Stderr, "slot must be in 0..%d, got %d\n", slotCount-1, *slot)
		os.Exit(2)
	}
	if *hbmAddr&0x1f != 0 {
		fmt.Fprintf(os.Stderr, "hbm-addr must be 32-byte aligned, got 0x%x\n", *hbmAddr)
		os.Exit(2)
	}
	if *chunkSize <= 0 || *chunkSize > 256 || *chunkSize%requestLineBytes != 0 {
		fmt.Fprintf(os.Stderr, "chunk-size must be a 64-byte multiple in range 64..256, got %d\n", *chunkSize)
		os.Exit(2)
	}
	if *recvBuffer < requestLineBytes {
		fmt.Fprintf(os.Stderr, "recv-buffer must be at least %d bytes, got %d\n", requestLineBytes, *recvBuffer)
		os.Exit(2)
	}
	if *cycles < 1 {
		fmt.Fprintf(os.Stderr, "cycles must be at least 1, got %d\n", *cycles)
		os.Exit(2)
	}

	orImage, err := loadImage("or_slot", *orPath, orSlotByte)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	patternImage, err := loadImage("pattern_slot", *patternPath, patternSlotByte)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// Stage the two images at disjoint addresses so each phase is a single
	// RECONF_ICAP with no re-upload, and so a slow previous stream can never
	// race an upload to the same region.
	orImage.addr = *hbmAddr
	patternImage.addr = orImage.addr + uint64(roundUp(len(orImage.data), 0x10000))
	if patternImage.addr+uint64(len(patternImage.data)) > 0x1_0000_0000 {
		fmt.Fprintf(os.Stderr, "staged images end above 0x100000000; lower -hbm-addr\n")
		os.Exit(2)
	}

	conn, err := net.DialTimeout("tcp", *addr, *timeout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect %s: %v\n", *addr, err)
		os.Exit(1)
	}
	defer conn.Close()

	if tcpConn, ok := conn.(*net.TCPConn); ok {
		if err := tcpConn.SetNoDelay(true); err != nil {
			fmt.Fprintf(os.Stderr, "set TCP_NODELAY: %v\n", err)
			os.Exit(1)
		}
		if err := tcpConn.SetReadBuffer(*recvBuffer); err != nil {
			fmt.Fprintf(os.Stderr, "set TCP read buffer: %v\n", err)
			os.Exit(1)
		}
	}

	slotID := byte(*slot)
	slotWorkload := uint16(*slot)
	startedAt := time.Now()

	for _, img := range []*image{orImage, patternImage} {
		uploadStarted := time.Now()
		if err := uploadBitstream(conn, *timeout, img.addr, img.data, *chunkSize, slotID, img.name); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Printf("%s: staged %dB at hbm_addr=0x%x (%s)\n", img.name, len(img.data), img.addr, time.Since(uploadStarted))
		if *verify {
			if err := verifyStaged(conn, *timeout, img.addr, img.data, img.name); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
		}
	}

	baseline, latency, err := probeSlot(conn, *timeout, slotWorkload)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	previous := classify(baseline)
	fmt.Printf("\nbaseline: slot %d answers as %s (byte0=0x%02x, latency %s)\n", *slot, previous, baseline[0], latency)
	if *dump {
		fmt.Print(hex.Dump(baseline))
	}

	// Build the program order. The default alternates pattern then or for the
	// requested number of cycles; -seq gives an explicit list, which is the
	// only way to make a partial the SECOND-or-later PR -- the case the default
	// never reaches and the one that just failed on hardware.
	byName := map[string]*image{
		"or": orImage, "o": orImage,
		"pattern": patternImage, "p": patternImage,
	}
	var program []*image
	if *seq != "" {
		for _, tok := range strings.Split(*seq, ",") {
			tok = strings.ToLower(strings.TrimSpace(tok))
			if tok == "" {
				continue
			}
			img, ok := byName[tok]
			if !ok {
				fmt.Fprintf(os.Stderr, "-seq token %q is not or|pattern\n", tok)
				os.Exit(2)
			}
			program = append(program, img)
		}
		if len(program) == 0 {
			fmt.Fprintln(os.Stderr, "-seq is empty")
			os.Exit(2)
		}
	} else {
		for cycle := 0; cycle < *cycles; cycle++ {
			program = append(program, patternImage, orImage)
		}
	}

	phases := 0
	matched := 0
	transitions := 0
	firstLanded := -1 // step index of the first PR whose result matched what was programmed AND changed the fabric
	failedAfterLand := false
	for step, img := range program {
		fmt.Printf("\n-- step %d/%d: programming %s --\n", step+1, len(program), img.name)
		if err := runReconfig(conn, *timeout, img.addr, len(img.data), slotID, img.name); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		time.Sleep(*settle)
		if *query {
			if err := queryStatus(conn, *timeout, slotID); err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
		}

		response, latency, err := probeSlot(conn, *timeout, slotWorkload)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		got := classify(response)
		phases++
		ok := response[0] == img.expect
		if ok {
			matched++
		}
		changed := got != previous
		if changed {
			transitions++
		}
		// A PR "landed" only when we can see it: it changed the fabric to the
		// programmed module. Programming the module already loaded is a no-op
		// we cannot distinguish from a dead ICAP, so it does not count.
		if ok && changed && firstLanded < 0 {
			firstLanded = step
		}
		if !ok && firstLanded >= 0 {
			failedAfterLand = true
		}
		verdict := "OK"
		if !ok {
			verdict = "MISMATCH"
		}
		fmt.Printf("probe: slot %d answers as %s, programmed %s -> %s (latency %s)\n", *slot, got, img.name, verdict, latency)
		if *dump || !ok {
			fmt.Print(hex.Dump(response))
		}
		previous = got
	}

	fmt.Printf("\nswap test: %d/%d phases answered as programmed, %d behavioural transition(s), %s total\n",
		matched, phases, transitions, time.Since(startedAt))
	switch {
	case matched == phases:
		fmt.Println("PASS: slot behaviour tracked every reconfiguration")
	case transitions == 0 && firstLanded < 0:
		fmt.Println("FAIL: no reconfiguration changed the fabric. The ICAP path or the")
		fmt.Println("full/partial pairing is wrong: confirm BOTH partials and the full")
		fmt.Println("bitstream on the card come from the same build's bitstreams directory.")
		os.Exit(1)
	case failedAfterLand:
		fmt.Println("PARTIAL: at least one reconfiguration DID change the fabric, so the ICAP")
		fmt.Println("path and the full/partial pairing are sound -- a later reconfiguration then")
		fmt.Println("did not land. This is a re-arm / ordering / per-module problem, NOT a dead")
		fmt.Println("ICAP. Compare a partial's success in step 1 vs. as a later step (-seq).")
		os.Exit(1)
	default:
		fmt.Println("INCONCLUSIVE: some phases matched only because the programmed module was")
		fmt.Println("already loaded (no visible change). Re-run with -seq so each step programs")
		fmt.Println("a different module from the one before it.")
		os.Exit(1)
	}
}
