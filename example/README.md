# Prebuilt bitstreams

The experiments in `eval/` run on these images, so the artifact can be
evaluated without a Vivado build. They target the Alveo U280
(`xcu280-fsvh2892-2L-e`).

| Path | Contents |
| --- | --- |
| `frac/jtag/frac.bit` | The full image, for `scripts/programfpga.sh`. `frac.bin` is the same image as a raw binary. |
| `frac/jtag/c<cell>_f<id>.bit` | One partial bitstream per cell and accelerator, for programming over JTAG. |
| `frac/icap/c<cell>_f<id>.bin` | The same partial bitstreams as the reconfiguration controller streams them into ICAP. `scripts/reconfslots.go` uploads these. The `.prm` files are Vivado's reports on them. |
| `frac/pcap/c<cell>_f<id>.bin` | The same again, without ICAP's per-byte bit swap. fRAC does not use them. |
| `frac/jtag/*.ltx` | Debug-probe files for the Vivado hardware manager. |
| `bypass/frac.bit` | The baseline without fRAC. The TCP stack echoes each request itself, with no reassembly or slots (Fig. 13, target `O_0`). |

The `<id>` of a partial bitstream is the accelerator's id in `spinhdl.yaml`:

| Cell | Slot | top_k | norm | log | or_slot | pattern_slot | cnn |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C00 | 0 | f00 | f01 | f02 | f06 | f07 | |
| C01 | 1 | f03 | f04 | f05 | f08 | f09 | |
| C02 | 2 | f10 | f11 | f12 | f13 | f14 | f20 |
| C03 | 3 | f15 | f16 | f17 | f18 | f19 | |

`log` is the paper's Logit accelerator and `norm` its Min-Max Normalization.
`or_slot` answers every line with all ones, and `pattern_slot` echoes every
line. Both are test units for probing slots and measuring throughput. The full
image starts with top_k in every cell.

A partial bitstream works only on the full image of its own build. A partial
from another build can report a successful load and still leave the slot's old
function in place.

## Provenance

- `frac/`: built on 2026-10-03 with Vivado 2022.2 by `bin/spinhdl weave` from
  this repository's sources. The base was commit 7a4f82b, plus the changes
  committed as 78c51d6.
- `bypass/frac.bit`: built on 2026-10-01 with Vivado 2022.2 as a flat (non-PR)
  design from branch `frac-bypass` of this repository, commit 243eb1b.

Both builds meet timing. A bitstream's build date can be checked in its
header: `head -c 160 frac/jtag/frac.bit | strings`.
