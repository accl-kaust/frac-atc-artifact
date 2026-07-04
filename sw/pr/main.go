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

	opWriteHBM     = 1
	opReconfICAP   = 3
	opQueryICAP    = 4
	defaultSlotC00 = 0

	errOK = 0
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

func sendOnly(conn net.Conn, timeout time.Duration, name string, request []byte) (time.Duration, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return 0, fmt.Errorf("set deadline for %s: %w", name, err)
	}

	startedAt := time.Now()
	if err := writeFull(conn, request); err != nil {
		return 0, fmt.Errorf("send %s request: %w", name, err)
	}
	return time.Since(startedAt), nil
}

func readFrame(conn net.Conn, timeout time.Duration, name string) ([]byte, time.Duration, error) {
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return nil, 0, fmt.Errorf("set deadline for %s: %w", name, err)
	}

	startedAt := time.Now()
	response := make([]byte, requestLineBytes)
	if _, err := io.ReadFull(conn, response); err != nil {
		return nil, 0, fmt.Errorf("read %s response: %w", name, err)
	}
	return response, time.Since(startedAt), nil
}

func sendAndReadStatus(conn net.Conn, timeout time.Duration, name string, request []byte) (time.Duration, time.Duration, []byte, error) {
	writeLatency, err := sendOnly(conn, timeout, name, request)
	if err != nil {
		return 0, 0, nil, err
	}

	response, readLatency, err := readFrame(conn, timeout, name)
	if err != nil {
		return writeLatency, 0, nil, err
	}
	return writeLatency, readLatency, response, nil
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

func sleepGap(gap time.Duration) {
	if gap > 0 {
		time.Sleep(gap)
	}
}

func probeWorkload(conn net.Conn, timeout time.Duration, workloadID uint16, label string, gap time.Duration) error {
	req := buildWorkloadRequest(workloadID)
	writeLatency, err := sendOnly(conn, timeout, label, req)
	if err != nil {
		return err
	}

	response, readLatency, err := readFrame(conn, timeout, label)
	if err != nil {
		return err
	}
	fmt.Printf("%s: workload=0x%04x sent=%dB write_latency=%s response_read_latency=%s response[0]=0x%02x\n", label, workloadID, len(req), writeLatency, readLatency, response[0])
	sleepGap(gap)
	return nil
}

func uploadBitstream(conn net.Conn, timeout time.Duration, hbmAddr uint64, prData []byte, chunkSize int, dumpRequests int) (int, error) {
	totalWritten := 0
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

		addr := hbmAddr + uint64(totalWritten)
		req := buildReconfRequest(opWriteHBM, defaultSlotC00, addr, uint64(len(chunk)), writePayload)
		writeIndex := offset / chunkSize
		if writeIndex < dumpRequests {
			fmt.Printf("WRITE_HBM[%d] request (%dB):\n%s", writeIndex, len(req), hex.Dump(req))
		}
		writeLatency, readLatency, response, err := sendAndReadStatus(conn, timeout, fmt.Sprintf("WRITE_HBM[%d]", writeIndex), req)
		if err != nil {
			return totalWritten, err
		}
		if !statusOK(response) {
			return totalWritten, fmt.Errorf("WRITE_HBM status not OK at offset=%d hbm_addr=0x%x:\n%s", offset, addr, hex.Dump(response))
		}

		fmt.Printf("WRITE_HBM: offset=%d hbm_addr=0x%x cmd_size=%dB payload=%dB request=%dB write_latency=%s status_read_latency=%s\n", offset, addr, len(chunk), len(writePayload), len(req), writeLatency, readLatency)
		totalWritten += len(chunk)
		offset = end
	}
	return totalWritten, nil
}

func runReconfig(conn net.Conn, timeout time.Duration, hbmAddr uint64, prSize int, slotID byte, gap time.Duration) error {
	req := buildReconfRequest(opReconfICAP, slotID, hbmAddr, uint64(prSize), nil)
	writeLatency, readLatency, response, err := sendAndReadStatus(conn, timeout, "RECONF_ICAP", req)
	if err != nil {
		return err
	}
	if !statusOK(response) {
		return fmt.Errorf("RECONF_ICAP status not OK:\n%s", hex.Dump(response))
	}
	fmt.Printf("RECONF_ICAP: slot=%d hbm_addr=0x%x size=%dB request=%dB write_latency=%s status_read_latency=%s\n", slotID, hbmAddr, prSize, len(req), writeLatency, readLatency)
	sleepGap(gap)
	return nil
}

func queryStatus(conn net.Conn, timeout time.Duration, slotID byte, gap time.Duration) error {
	req := buildReconfRequest(opQueryICAP, slotID, 0, 0, nil)
	writeLatency, readLatency, response, err := sendAndReadStatus(conn, timeout, "QUERY_ICAP_STATUS", req)
	if err != nil {
		return err
	}
	if !responseCodeOK(response) {
		return fmt.Errorf("QUERY_ICAP_STATUS status not OK:\n%s", hex.Dump(response))
	}
	fmt.Printf("QUERY_ICAP_STATUS: request=%dB write_latency=%s status_read_latency=%s\n", len(req), writeLatency, readLatency)
	sleepGap(gap)
	return nil
}

func main() {
	addr := flag.String("addr", defaultServerAddress, "TCP server address")
	hbmAddr := flag.Uint64("hbm-addr", 0x4000, "32-byte-aligned HBM byte address for bitstream upload")
	chunkSize := flag.Int("chunk-size", 64, "maximum raw bitstream bytes per HBM write request")
	timeout := flag.Duration("timeout", 10*time.Second, "dial/read/write timeout")
	recvBuffer := flag.Int("recv-buffer", 2048, "TCP receive buffer size in bytes")
	sendGap := flag.Duration("send-gap", time.Millisecond, "delay after probe/reconfig/status requests")
	statusDelay := flag.Duration("status-delay", 5*time.Millisecond, "delay after RECONF_ICAP before QUERY_ICAP_STATUS")
	preProbes := flag.Bool("pre-probes", false, "send C00/C01 workload probes before HBM upload")
	queryAfterReconfig := flag.Bool("query-status", false, "send QUERY_ICAP_STATUS after RECONF_ICAP")
	postProbe := flag.Bool("post-probe", false, "send C00 workload probe after RECONF_ICAP")
	dumpRequests := flag.Int("dump-requests", 0, "hex dump this many WRITE_HBM requests before sending")
	flag.Parse()

	if flag.NArg() != 1 {
		fmt.Fprintf(os.Stderr, "usage: %s [flags] BITSTREAM\n", os.Args[0])
		os.Exit(2)
	}
	if *hbmAddr&0x1f != 0 {
		fmt.Fprintf(os.Stderr, "hbm-addr must be 32-byte aligned, got 0x%x\n", *hbmAddr)
		os.Exit(2)
	}
	if *hbmAddr >= 0x1_0000_0000 {
		fmt.Fprintf(os.Stderr, "hbm-addr must be below 0x100000000, got 0x%x\n", *hbmAddr)
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
	if *dumpRequests < 0 {
		fmt.Fprintf(os.Stderr, "dump-requests must be non-negative, got %d\n", *dumpRequests)
		os.Exit(2)
	}

	bitstreamPath := flag.Arg(0)
	bitstream, err := os.ReadFile(bitstreamPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read bitstream %s: %v\n", bitstreamPath, err)
		os.Exit(1)
	}
	if len(bitstream) == 0 {
		fmt.Fprintf(os.Stderr, "bitstream %s is empty\n", bitstreamPath)
		os.Exit(2)
	}
	prSize := roundUp(len(bitstream), 4)
	prData := padCopy(bitstream, prSize)
	fmt.Printf("bitstream: file=%s original=%dB pr_size=%dB hbm_addr=0x%x\n", bitstreamPath, len(bitstream), prSize, *hbmAddr)

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

	startedAt := time.Now()

	if *preProbes {
		if err := probeWorkload(conn, *timeout, 0x0000, "PRE_C00_WORKLOAD", *sendGap); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := probeWorkload(conn, *timeout, 0x0001, "PRE_C01_WORKLOAD", *sendGap); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}

	written, err := uploadBitstream(conn, *timeout, *hbmAddr, prData, *chunkSize, *dumpRequests)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("upload complete: pr_size=%dB hbm_written=%dB\n", prSize, written)

	if err := runReconfig(conn, *timeout, *hbmAddr, prSize, defaultSlotC00, *sendGap); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *queryAfterReconfig {
		time.Sleep(*statusDelay)
		if err := queryStatus(conn, *timeout, defaultSlotC00, *sendGap); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}

	if *postProbe {
		if err := probeWorkload(conn, *timeout, 0x0000, "POST_C00_WORKLOAD", *sendGap); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}

	fmt.Printf("completed PR board test in %s\n", time.Since(startedAt))
}
