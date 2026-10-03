#!/usr/bin/env bash
# Four fperf processes at once, N clients each (1 by default), each sending
# 4096-byte requests to a different top_k slot.  Each process's output goes to its own
# log, and every request's latency (fperf -L 1) to slot<s>/hugepage_thread_*.txt.
# The FPGA must already hold an image with top_k in slots 0-3.
#
#   ./four_topk.sh             logs in ./four_topk_<time>/slot0.log .. slot3.log
#   D=60 ./four_topk.sh        60-second runs
#   N=7 ./four_topk.sh         7 clients per slot, 28 in all; slot s uses cpus s*N .. s*N+N-1
#   NIC=<iface> ./four_topk.sh when the port to the FPGA is not found by itself
set -euo pipefail

FPGA=${FPGA:-172.24.1.52}
PORT=${PORT:-2888}
D=${D:-30}                                   # seconds per run
M=${M:-4096}                                 # request bytes; top_k answers 64
N=${N:-1}                                    # clients per slot, one cpu each
START=${START:-0}                            # first cpu
TPA=${TPA:-$HOME/.local/bin/tpa}
FPERF=${FPERF:-$HOME/libtpa/build/bin/app/fperf}
TPA_CFG=${TPA_CFG:-"tcp {tso = 0; } dpdk { socket-mem = 8192; mbuf_mem_size = 6GB; }"}
OUT=${OUT:-four_topk_$(date +%Y-%m-%dT%H%M%S)}

if [ -z "${NIC:-}" ]; then                   # the interface with a direct route to the FPGA
    route=$(ip -o route get "$FPGA")
    case "$route" in *" via "*) route= ;; esac
    NIC=$(awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$route")
fi
[ -n "$NIC" ] || { echo "no interface has a direct route to $FPGA; set NIC" >&2; exit 1; }

if [ $((START + 4 * N)) -gt "$(nproc)" ]; then
    echo "4 x $N clients from cpu $START need more than the $(nproc) cpus here" >&2
    exit 1
fi
mkdir -p "$OUT"
sudo -v                                      # ask for the password once, before the background jobs

# Background jobs of a script ignore Ctrl-C, so pass it on to the fperfs.
trap 'sudo pkill -INT -f "$FPERF" 2>/dev/null; wait' INT TERM

pids=()
lat=()
for slot in 0 1 2 3; do
    # fperf joins -D and the file name in a 64-byte buffer: keep -D short.
    lat+=("$(mktemp -d /tmp/feXXXXXX)")
    sudo env TPA_ID="client$slot" TPA_ETH_DEV="$NIC" TPA_CFG="$TPA_CFG" \
        "$TPA" run "$FPERF" -c "$FPGA" -p "$PORT" -t rr -d "$D" -n "$N" -S "$((START + slot * N))" \
        -m "$M" -X "$M" -R 64 -C 1 -Z 1 -K "$slot" -L 1 -D "${lat[$slot]}" \
        > "$OUT/slot$slot.log" 2>&1 &
    pids+=($!)
done
echo "4 fperf processes, $N clients each, on $NIC for ${D}s, logging to $OUT/slot0.log .. slot3.log"

rc=0
for pid in "${pids[@]}"; do
    wait "$pid" || rc=1
done
for slot in 0 1 2 3; do                      # fperf writes the latencies as it exits
    mkdir -p "$OUT/slot$slot"
    mv "${lat[$slot]}"/* "$OUT/slot$slot/" 2>/dev/null || echo "slot $slot: no latency file" >&2
    rm -rf "${lat[$slot]}"
done

# Mean of fperf's per-second, per-client average latency from second 10 on.
for slot in 0 1 2 3; do
    awk -v slot="$slot" '$2 == "RR" && $3 ~ /^\./ && $1 >= 10 {
            split($5, a, "="); sub("us", "", a[2]); sum += a[2]; n++ }
        END { if (n) printf "slot %s: %.2f us mean latency over %d client-seconds\n", slot, sum / n, n
              else  printf "slot %s: no data, see the log\n", slot }' "$OUT/slot$slot.log"
done
exit "$rc"
