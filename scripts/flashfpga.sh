#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
usage: $(basename "$0") <file.bit | file.mcs>
       $(basename "$0") -h | --help

Writes a full image into the U280's configuration flash over JTAG, so that the
card boots it at power-up.  A .bit is first made into an .mcs that places it at
OFFSET; an .mcs is written as it is.  The image runs after the next power
cycle -- a reboot does not reload the FPGA.

0x01002000 is where Alveo cards keep the image that the factory (golden) image
at address 0 jumps to at power-up: the XRT shell, as shipped.  Writing there
keeps the golden image as the fallback, so a card whose new image does not
load comes up as golden (PCIe 10ee:d00c).

Vivado writes the flash through a helper design it loads into the FPGA first,
so the FPGA is reconfigured.  A card that is up on PCIe drops its link, which
some hosts (firmware-first AMD servers) answer with a reset.  Take such a card
off the bus and turn its link off before running this:

  for f in /sys/bus/pci/devices/0000:01:00.*; do echo 1 | sudo tee \$f/remove; done
  sudo setpci -s <root port above it> CAP_EXP+10.w=0010:0010      # Link Disable

environment:
  OFFSET       flash address of the image  (default 0x01002000)
  FLASH_PART   Vivado cfgmem part          (default mt25qu01g-spi-x1_x2_x4, the U280's)
  VIVADO_ROOT  Vivado install              (default /tools/Xilinx/Vivado/2022.2)
  VIVADO       vivado binary               (default \$VIVADO_ROOT/bin/vivado)
  HW_SERVER    hw_server URL               (default localhost:3121)
  HW_TARGET    JTAG target to open         (default the first one found)
  JTAG_HZ      JTAG clock, such as 30000000 (default the cable's, often 15 MHz);
               the erase, program and verify take 10-30 minutes at 15 MHz
  LOG          Vivado's full output        (default /tmp/flashfpga-\$USER.log)
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }
IMAGE="$1"
[ -f "$IMAGE" ] || { echo "no such file: $IMAGE" >&2; exit 1; }
IMAGE="$(readlink -f "$IMAGE")"
case "$IMAGE" in
    *.bit|*.mcs) ;;
    *) echo "$IMAGE: give a .bit or an .mcs" >&2; exit 1 ;;
esac

OFFSET="${OFFSET:-0x01002000}"
FLASH_PART="${FLASH_PART:-mt25qu01g-spi-x1_x2_x4}"
VIVADO_ROOT="${VIVADO_ROOT:-/tools/Xilinx/Vivado/2022.2}"
VIVADO="${VIVADO:-$VIVADO_ROOT/bin/vivado}"
HW_SERVER="${HW_SERVER:-localhost:3121}"
HW_TARGET="${HW_TARGET:-}"
JTAG_HZ="${JTAG_HZ:-}"
LOG="${LOG:-/tmp/flashfpga-$USER.log}"

if [ "${HW_SERVER%%:*}" = localhost ] && ! pgrep -x hw_server >/dev/null; then
    setsid nohup "$VIVADO_ROOT/bin/hw_server" >/tmp/hw_server.log 2>&1 </dev/null &
    sleep 8
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat >"$WORK/flash.tcl" <<'EOF'
lassign $argv image mcs offset part url target hz
if {[string match *.bit $image]} {
    # 128 MB, the U280's 1 Gb flash, read four bits at a time
    write_cfgmem -force -format mcs -size 128 -interface SPIx4 \
        -loadbit [list up $offset $image] -checksum -file $mcs
} else {
    set mcs $image
}
open_hw_manager
connect_hw_server -url $url
set targets [get_hw_targets -quiet]
if {$target ne ""} { set targets [get_hw_targets -quiet $target] }
if {[llength $targets] == 0} { puts "FLASH_FAIL: no JTAG target"; exit 1 }
if {$hz ne ""} { set_property PARAM.FREQUENCY $hz [lindex $targets 0] }
open_hw_target [lindex $targets 0]
set devs [get_hw_devices -quiet xcu280*]
if {[llength $devs] == 0} { set devs [get_hw_devices] }
set dev [lindex $devs 0]
current_hw_device $dev
set parts [get_cfgmem_parts -quiet $part]
if {[llength $parts] == 0} { puts "FLASH_FAIL: Vivado has no flash part $part"; exit 1 }
create_hw_cfgmem -hw_device $dev [lindex $parts 0]
set mem [get_property PROGRAM.HW_CFGMEM $dev]
# erase and write only the sectors the image covers, then read them back
set_property PROGRAM.ADDRESS_RANGE {use_file} $mem
set_property PROGRAM.FILES [list $mcs] $mem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $mem
set_property PROGRAM.BLANK_CHECK 0 $mem
set_property PROGRAM.ERASE 1 $mem
set_property PROGRAM.CFG_PROGRAM 1 $mem
set_property PROGRAM.VERIFY 1 $mem
set_property PROGRAM.CHECKSUM 0 $mem
# the helper design between JTAG and the flash: this reconfigures the FPGA
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
if {[catch {program_hw_devices $dev} err]} { puts "FLASH_FAIL: loading the flash helper: $err"; exit 1 }
refresh_hw_device $dev
if {[catch {program_hw_cfgmem -hw_cfgmem $mem} err]} { puts "FLASH_FAIL: $err"; exit 1 }
close_hw_target
puts "FLASH_OK: $mcs written to the flash of $dev"
EOF

case "$IMAGE" in
    *.bit) echo "making a flash image of $IMAGE at $OFFSET, then writing it; this takes a while" ;;
    *)     echo "writing $IMAGE; this takes a while" ;;
esac
echo "full Vivado output: $LOG"
set +e
"$VIVADO" -mode batch -nolog -nojournal -notrace -source "$WORK/flash.tcl" \
    -tclargs "$IMAGE" "$WORK/flash.mcs" "$OFFSET" "$FLASH_PART" "$HW_SERVER" "$HW_TARGET" "$JTAG_HZ" 2>&1 |
    tee "$LOG" | grep --line-buffered -E "FLASH_|ERROR|CRITICAL WARNING|Operation|Mfg ID|completed successfully"
rc=${PIPESTATUS[0]}
set -e
if [ "$rc" -ne 0 ] || ! grep -q "^FLASH_OK" "$LOG"; then
    echo "writing the flash failed (vivado exit status $rc); the end of $LOG:" >&2
    tail -n 30 "$LOG" >&2
    [ "$rc" -ne 0 ] || rc=1
fi
exit "$rc"
