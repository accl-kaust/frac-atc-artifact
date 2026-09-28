#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
usage: $(basename "$0") <file.bit>
       $(basename "$0") -h | --help

Programs a bitstream onto the FPGA over JTAG with the Vivado hardware
manager: a full image, or a partial .bit for one slot.  Starts a local
hw_server first if none is running, opens the first JTAG target and
programs the xcu280 on it (else its first device).  Prints PROGRAM_OK on
success; exits non-zero on failure.

environment:
  VIVADO_ROOT  Vivado install         (default /tools/Xilinx/Vivado/2022.2)
  VIVADO       vivado binary          (default \$VIVADO_ROOT/bin/vivado)
  HW_SERVER    hw_server URL          (default localhost:3121)
  HW_TARGET    JTAG target to open    (default the first one found)

example:
  $(basename "$0") fpga.bit 
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac
[ $# -eq 1 ] || { usage >&2; exit 1; }
BIT="$1"
[ -f "$BIT" ] || { echo "no such file: $BIT" >&2; exit 1; }
BIT="$(readlink -f "$BIT")"

VIVADO_ROOT="${VIVADO_ROOT:-/tools/Xilinx/Vivado/2022.2}"
VIVADO="${VIVADO:-$VIVADO_ROOT/bin/vivado}"
HW_SERVER="${HW_SERVER:-localhost:3121}"
HW_TARGET="${HW_TARGET:-}"

if [ "${HW_SERVER%%:*}" = localhost ] && ! pgrep -x hw_server >/dev/null; then
    setsid nohup "$VIVADO_ROOT/bin/hw_server" >/tmp/hw_server.log 2>&1 </dev/null &
    sleep 8
fi

TCL="$(mktemp --suffix=.tcl)"
trap 'rm -f "$TCL"' EXIT
cat >"$TCL" <<'EOF'
lassign $argv bit url target
open_hw_manager
connect_hw_server -url $url
set targets [get_hw_targets -quiet]
if {$target ne ""} { set targets [get_hw_targets -quiet $target] }
if {[llength $targets] == 0} { puts "PROGRAM_FAIL: no JTAG target"; exit 1 }
open_hw_target [lindex $targets 0]
set devs [get_hw_devices -quiet xcu280*]
if {[llength $devs] == 0} { set devs [get_hw_devices] }
set dev [lindex $devs 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
if {[catch {program_hw_devices $dev} err]} { puts "PROGRAM_FAIL: $err"; exit 1 }
refresh_hw_device -quiet $dev
close_hw_target
puts "PROGRAM_OK: $dev"
EOF

echo "programming $BIT"
set +e
"$VIVADO" -mode batch -nolog -nojournal -notrace -source "$TCL" -tclargs "$BIT" "$HW_SERVER" "$HW_TARGET" 2>&1 |
    grep -E "PROGRAM_|ERROR|CRITICAL WARNING"
rc=${PIPESTATUS[0]}
set -e
exit "$rc"
