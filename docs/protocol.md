# Reconfiguration Network Protocol

## Transport

The standalone design exposes a TCP service on port `2888`. Reconfiguration
requests use workload ID `0x00ab`. All multi-byte protocol fields are
little-endian.

Every request consists of:

```text
64-byte fRAC request header
64-byte reconfiguration command
optional payload, padded to complete 64-byte network lines
```

The response is one 64-byte line.

## fRAC Request Header

The Go client constructs the outer header as follows:

| Bytes | Size | Field |
| --- | ---: | --- |
| 0-55 | 56 | Prefix. The current client writes `0xff`; current request framing does not require this value as a sentinel. |
| 56-59 | 4 | Declared request size, little-endian. |
| 60-61 | 2 | Top-level configuration and request flags. Bits 1:0 are `FIRST` and `LAST`. |
| 62-63 | 2 | Workload ID, `0x00ab` for the reconfiguration controller. |

For controller requests, the declared size is the command line plus padded
payload. It excludes the outer 64-byte header. The dispatcher accounts for this
controller-specific header when tracking request completion.

The current client marks every controller request as both first and last. A
query or reconfiguration command therefore has a declared size of 64 bytes and
occupies 128 TCP payload bytes including the outer header.

## Command Format

The controller consumes exactly one 64-byte command line:

| Bytes | Size | Field |
| --- | ---: | --- |
| 0 | 1 | Opcode |
| 1 | 1 | Slot ID |
| 2-7 | 6 | Reserved; ignored by current RTL |
| 8-15 | 8 | HBM byte address |
| 16-23 | 8 | Byte count |
| 24-63 | 40 | Reserved; ignored by current RTL |

The command line's AXI-Stream `tkeep` and `tlast` values are not validated.

## Opcodes

| Value | Name | Request body | Successful response |
| ---: | --- | --- | --- |
| 1 | `WRITE_HBM` | Payload bytes to write after the command | Standard status response with code 0 |
| 2 | `READ_HBM` | None | Raw HBM data, zero-padded to 64 bytes |
| 3 | `RECONF_ICAP` | None; bitstream must already be in HBM | Standard status response after `PRDONE` or `PRERROR` |
| 4 | `QUERY_STATUS` | None | Structured query response |

### WRITE_HBM

The address must be 32-byte aligned and the size must be nonzero. The payload
may be padded to a 64-byte network boundary, but the command's byte count must
contain only the number of meaningful bytes. The controller ignores extra
padding after writing the requested count.

The operation does not select a slot; byte 1 is ignored.

### READ_HBM

The address must be 32-byte aligned. Size must be between 1 and 64 bytes. The
success response contains data beginning at byte 0, with bytes beyond the
requested size set to zero. There is no leading success code in a successful
read response.

The operation does not select a slot; byte 1 is ignored.

### RECONF_ICAP

The address must be 32-byte aligned. Size must be nonzero and divisible by four.
The slot must be less than the integrated `SLOT_COUNT`, currently three. The
specified HBM range must contain an ICAP-compatible partial bitstream.

The response is delayed until the ICAP operation reports completion or error.
There is no controller timeout.

### QUERY_STATUS

Address, size, and slot fields are ignored. This opcode bypasses address and
size validation, so a zero size is valid. A query can only be accepted while
the controller is in `IDLE`.

## Validation Order

When a command is accepted, validation occurs in this order:

1. Opcode is recognized.
2. `QUERY_STATUS` is handled immediately.
3. Address fits the 33-bit controller address width.
4. Address is aligned to 32 bytes.
5. Size is nonzero.
6. A read size is no greater than 64 bytes.
7. A reconfiguration size is divisible by four.
8. A reconfiguration slot ID is in range.

Only the first detected error is returned.

## Standard Status Response

Write, reconfiguration, and validation results use one 64-byte response:

| Bytes | Field |
| --- | --- |
| 0 | Status/error code |
| 1-63 | Zero |

All 64 `tkeep` bits are asserted and `tlast` is asserted.

## Error Codes

| Code | Name | Meaning |
| ---: | --- | --- |
| 0 | `ERR_OK` | Operation completed successfully |
| 1 | `ERR_OPCODE` | Unknown opcode |
| 2 | `ERR_ALIGN` | HBM address is not 32-byte aligned |
| 3 | `ERR_SIZE` | Size is zero, read exceeds 64 bytes, or ICAP size is not divisible by four |
| 4 | `ERR_ADDR` | Address does not fit the controller's 33-bit address width |
| 5 | `ERR_AXI_BRESP` | HBM write response was not OKAY |
| 6 | `ERR_AXI_RRESP` | HBM read response was not OKAY |
| 7 | `ERR_RLAST` | HBM read burst ended at an unexpected beat |
| 8 | `ERR_SLOT` | Reconfiguration slot ID is outside the integrated range |
| 9 | `ERR_ICAP` | ICAP asserted `PRERROR` |

## Query Status Response

`QUERY_STATUS` returns one 64-byte structured response:

| Bytes | Size | Field |
| --- | ---: | --- |
| 0 | 1 | Query command result; currently always `ERR_OK` for an accepted query |
| 1 | 1 | Reconfiguration active, encoded as 0 or 1 |
| 2 | 1 | Most recently completed slot ID |
| 3 | 1 | Most recent controller error |
| 4 | 1 | Current ICAP `AVAIL`, encoded as 0 or 1 |
| 5 | 1 | `PRDONE` was observed, encoded as 0 or 1 |
| 6 | 1 | `PRERROR` was observed, encoded as 0 or 1 |
| 7 | 1 | Reserved; zero |
| 8-15 | 8 | Last reconfiguration cycle count |
| 16-23 | 8 | Current cycle count if active, otherwise zero |
| 24-63 | 40 | Reserved; zero |

The query's byte 0 reports whether the query itself was accepted. The stored
result of the preceding operation is in byte 3. Clients must inspect byte 3 and
must not infer the last reconfiguration result from byte 0.

The current Go client verifies only byte 0 and does not print the structured
fields.

## Example Encoding

The following command requests reconfiguration of slot 0 from 4096 bytes at HBM
address `0x4000`:

```text
03 00 00 00 00 00 00 00  00 40 00 00 00 00 00 00
00 10 00 00 00 00 00 00  00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00
```

The first byte is opcode 3, byte 1 selects slot 0, bytes 8-15 contain
`0x4000`, and bytes 16-23 contain `0x1000`.

## Protocol Limitations

The current ABI has no version, request ID, checksum, authentication tag, or
artifact identity. Commands are serialized because the controller accepts a new
command only in `IDLE`. Malformed write requests can wait indefinitely if they
provide fewer payload bytes than declared, and malformed reconfiguration data
can wait indefinitely for an ICAP result.
