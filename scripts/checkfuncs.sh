#!/usr/bin/env bash
# Check what each accelerator answers, in every cell: load the unit's partial
# into the slots with reconfslots.go, then let checkfuncs.go send requests of
# known data and compare the answers with the ones it works out itself.
#
# The FPGA must hold the full image of the build the partials come from: set
# BIT to program it first.  That image starts every slot with the top_k it
# was built with, which may be older than the partial, so the partials are
# always loaded, top_k's too.  The slots are left holding the last unit
# checked.
#
#   scripts/checkfuncs.sh                         top_k, norm and log in slots 0-3
#   BIT=build/frac/bitstreams/jtag/frac.bit scripts/checkfuncs.sh
#   UNITS=log SLOTS="1 2" scripts/checkfuncs.sh   log in slots 1 and 2
#   ICAP=example/icap scripts/checkfuncs.sh       another build's partials
#   scripts/checkfuncs.sh -reqs 64 -seed 7        arguments go to checkfuncs.go
#
# Run it from the repository root.  It needs no sudo.  It takes the lock
# eval/run.py takes, so the two never share the FPGA.
set -euo pipefail

FPGA=${FPGA:-172.24.1.52:2888}
BIT=${BIT:-}                                  # a full image to program first, if set
ICAP=${ICAP:-build/frac/bitstreams/icap}      # the partials, c<cell>_f<rm id>.bin
# their rm ids: the build's own spinhdl.yaml when it kept one, else the repo's
SPINHDL=${SPINHDL:-$( [ -f "$ICAP/../spinhdl.yaml" ] && echo "$ICAP/../spinhdl.yaml" || echo spinhdl.yaml )}
UNITS=${UNITS:-"top_k norm log"}
SLOTS=${SLOTS:-"0 1 2 3"}
CHUNK=${CHUNK:-256}                           # reconfslots -chunk-size
HBM=${HBM:-0x10004000}                        # reconfslots -hbm-addr
GO=${GO:-go}

command -v "$GO" >/dev/null 2>&1 || GO=/usr/local/go/bin/go
[ -f "$SPINHDL" ] || { echo "no $SPINHDL here: run from the repository root, or set SPINHDL" >&2; exit 2; }
[ -d "$ICAP" ] || { echo "no partials in $ICAP: set ICAP" >&2; exit 2; }
[ -z "$BIT" ] || [ -f "$BIT" ] || { echo "no $BIT" >&2; exit 2; }

# "<slot> <unit> <rm id>" for every reconfigurable module spinhdl.yaml lists
rms=$(awk '
    /^[[:space:]]*slot_id:/ { slot = $2 }
    /^[[:space:]]*id:/      { id = $2; next }
    /^[[:space:]]*unit:/    { if (id != "" && slot != "") print slot, $2, id }
    { id = "" }' "$SPINHDL")

partial() {                                   # slot unit -> its partial bitstream
    local id
    id=$(awk -v s="$1" -v u="$2" '$1 == s && $2 == u { print $3; exit }' <<<"$rms")
    [ -n "$id" ] || { echo "$SPINHDL has no $2 in slot $1" >&2; return 1; }
    printf '%s/c%02d_f%02d.bin\n' "$ICAP" "$1" "$id"
}

for unit in $UNITS; do                        # every partial, before the FPGA is touched
    for slot in $SLOTS; do
        p=$(partial "$slot" "$unit")
        [ -f "$p" ] || { echo "no $p" >&2; exit 2; }
    done
done

# eval/run.py's lock.  Open it read-only, and create it only when it is
# missing: with fs.protected_regular, creating over another user's file fails.
lock=${TMPDIR:-/tmp}/frac-eval-run.lock
[ -e "$lock" ] || (umask 0 && : >>"$lock") 2>/dev/null || true
exec 9<"$lock"
flock -n 9 || { echo "eval/run.py, or another check, is using the FPGA" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"$GO" build -o "$tmp/reconfslots" scripts/reconfslots.go
"$GO" build -o "$tmp/checkfuncs" scripts/checkfuncs.go

host=${FPGA%:*}
if [ -n "$BIT" ]; then
    scripts/programfpga.sh "$BIT"
    sleep 10                                  # as eval/run.py: settle, then wait for the link
    for _ in $(seq 45); do
        ping -c 1 -W 1 "$host" >/dev/null 2>&1 && break
        sleep 1
    done
fi
ping -c 1 -W 2 "$host" >/dev/null 2>&1 \
    || { echo "$host does not answer ping: program the FPGA first (BIT=...)" >&2; exit 1; }

failed=()
for unit in $UNITS; do
    for slot in $SLOTS; do
        p=$(partial "$slot" "$unit")
        if ! "$tmp/reconfslots" -addr "$FPGA" -slot "$slot" -chunk-size "$CHUNK" -hbm-addr "$HBM" \
                -query-status "$p" >"$tmp/reconf.out" 2>&1; then
            cat "$tmp/reconf.out" >&2
            echo "reconfslots could not load $p into slot $slot" >&2
            exit 1
        fi
        echo "loaded $p into slot $slot"
    done
    echo
    "$tmp/checkfuncs" -addr "$FPGA" -unit "$unit" -slots "$(echo $SLOTS | tr ' ' ',')" "$@" || failed+=("$unit")
    echo
done

if [ ${#failed[@]} -ne 0 ]; then
    echo "FAIL: ${failed[*]}"
    exit 1
fi
echo "ok: $UNITS answered right in slots $SLOTS"
