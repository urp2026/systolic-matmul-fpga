# systolic-matmul-fpga

**A weight-stationary systolic array for integer matrix multiplication — measuring the real cost of multiplier microarchitecture and data width on FPGA.**

![Platform](https://img.shields.io/badge/platform-Artix--7%20XC7A100T-blue)
![HDL](https://img.shields.io/badge/HDL-Verilog-orange)
![Tools](https://img.shields.io/badge/tools-Vivado%202025.2%20%7C%20Icarus-lightgrey)
![Status](https://img.shields.io/badge/status-complete-brightgreen)

A 4×4 weight-stationary systolic array implemented on a Digilent Nexys A7-100T, built six times over — three integer precisions (INT4 / INT8 / INT16) × two multiplier microarchitectures (array vs. Wallace tree) — and measured end to end for power, performance, area, and numerical accuracy.

---

## Table of Contents

- [Motivation](#motivation)
- [Key Findings](#key-findings)
- [Results](#results)
- [Architecture](#architecture)
- [Verification](#verification)
- [Measurement Methodology](#measurement-methodology)
- [Analysis](#analysis)
- [Limitations](#limitations)
- [Future Work](#future-work)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Authors](#authors)

---

## Motivation

Matrix multiplication dominates neural network inference. When accelerating it in dedicated hardware, a designer faces two largely independent choices:

**1. Multiplier microarchitecture.** An *array* multiplier sums partial products sequentially; a *Wallace tree* compresses them through a CSA (carry-save adder) tree before a single final addition. Textbooks say the Wallace tree wins, since its adder depth is O(log n).

**2. Data width.** Replacing FP32 with INT8 or INT4 shrinks area and power, at the cost of rounding error.

This project quantifies both axes by *measuring* them on real FPGA silicon rather than reasoning about them analytically. Specifically:

1. Does a Wallace tree actually pay off on an FPGA versus an array multiplier? If so, on which metric, and under what conditions?
2. When data width shrinks, at what exchange rate is precision traded for resources?
3. Are the two axes independent?

**Target hardware:** Digilent Nexys A7-100T (Xilinx Artix-7 `xc7a100tcsg324-1`)
**Toolchain:** Verilog · Vivado 2025.2 · Icarus Verilog · Python/NumPy

---

## Key Findings

> **1. The Wallace tree's advantage depends on data width.** It loses on every metric at INT4, crosses over at INT8, and by INT16 delivers −16.1% area, +3.4% speed, and −16.7% power. All three move monotonically in the same direction.

> **2. The *mechanism* of that advantage changes with width.** At INT8 the gain comes from CARRY4 reduction improving placement density; at INT16 it comes from a genuine reduction in combinational logic.

> **3. The FPGA's dedicated carry chain cancels the textbook speed advantage.** A CARRY4 stage is roughly 3× faster than a LUT path, and this effect dominates at narrow widths. Only at INT16 does tree depth overcome it.

> **4. Narrowing data width is a clean trade-off.** INT8 → INT4 gives up 25 dB of SQNR to save ~40% of resources and power. Measured SQNR tracks the theoretical 6.02 dB/bit.

> **5. The two axes are independent.** Multiplier structure has zero effect on accuracy, so it can be chosen on cost alone.

---

## Results

### Full measurement matrix (6 configurations)

| DW | Multiplier | LUT | CARRY4 | FF | Slice | WNS (ns) | Fmax | Dynamic |
|---|---|---|---|---|---|---|---|---|
| 16 | Array | 917 | 180 | 429 | 329 | −0.086 | 99.1 MHz | 12 mW |
| 16 | Wallace | 829 | 180 | 426 | 276 | +0.230 | 102.4 MHz | 10 mW |
| 8 | Array | 781 | 132 | 426 | 285 | +0.476 | 105.0 MHz | 10 mW |
| 8 | Wallace | 779 | 52 | 426 | 261 | +0.317 | 103.3 MHz | 9 mW |
| 4 | Array | 479 | 68 | 373 | 171 | +1.599 | 119.0 MHz | 6 mW |
| 4 | Wallace | 518 | 68 | 373 | 204 | +0.674 | 107.2 MHz | 7 mW |

> Fmax is derived from WNS under a 10 ns constraint as `1 / (T − WNS)`. DSP usage is zero across all configurations, confirming that multipliers were mapped to LUTs. INT16 Array is the only configuration that fails timing (negative WNS).

### Relative performance — Wallace vs. Array

| DW | Partial products | LUT | CARRY4 | Slice | Fmax | Dynamic |
|---|---|---|---|---|---|---|
| 4 | 4 | +8.1% | 0% | **+19.3%** | **−9.9%** | +16.7% |
| 8 | 8 | −0.3% | −60.6% | −8.4% | −1.6% | −10.0% |
| 16 | 16 | −9.6% | 0% | **−16.1%** | **+3.4%** | −16.7% |

Negative is better for LUT/CARRY4/Slice/Dynamic; positive is better for Fmax.

### Precision loss (SQNR)

| Precision | Representable range | AW | SQNR | vs. INT8 |
|---|---|---|---|---|
| INT4 | −8 … +7 | 16 | 12.9 dB | −25.2 dB |
| INT8 | −128 … +127 | 32 | 38.1 dB | (baseline) |
| INT16 | −32768 … +32767 | 64 | 86.4 dB | +48.3 dB |

> Mean of 20 runs on 64×64 normally-distributed matrices, symmetric per-tensor scaling.

Because the two multiplier structures are bit-exact equivalents, exactly one SQNR value exists per precision.

---

## Architecture

A 4×4 weight-stationary systolic array. Sixteen processing elements (PEs) are laid out in a grid, each holding one multiplier and one accumulator register. Only the data width `DW` and the multiplier module are swapped between configurations — the dataflow is byte-for-byte identical across all six builds, so any measured difference is attributable to those two variables alone.

```
matmul_top_ws
 └ systolic_array_ws (u_sa)      ← identical across all configurations
    └ pe_ws × 16                 ← identical across all configurations
       └ u_mul                   ← the only swapped module
          array_multiplier_signed  ⇄  wallace_multiplier_signed
```

### Design decisions

| Item | Choice | Rationale |
|---|---|---|
| Signed multiplication | Baugh-Wooley | Handles sign inside the partial-product array, no sign extension needed |
| Multiplier alternative | Wallace tree (CSA) | Isolates the effect of partial-product compression on adder depth |
| Accumulator width | `AW = 4 × DW` | 16/32/64 bit for INT4/8/16 — safe margin over the required 10/18/34 bit |
| Top-level split | `fpga_top_bram` / `power_bench_wrapper` | Separates board bring-up from measurement |
| Power stimulus | LFSR pseudo-random inputs | Static inputs produce no switching, so dynamic power would read as zero |

### Measurement boundary

Resources and power are measured at the `power_bench_wrapper` level. The LFSR stimulus logic costs 8 slices at INT8 (2.8% of the total) — negligible for relative comparison between configurations. `fpga_top_bram` is unsuitable as a measurement target because its 7-segment BCD conversion logic accounts for more than half of total LUT usage.

---

## Verification

Two verification activities with fundamentally different purposes. Conflating them distorts the interpretation of results, so they are kept explicitly separate.

### ① RTL correctness

**Question:** does the hardware compute the given integer matrix product exactly?

```
integer test cases → .mem files → RTL simulation → compare against golden
     (Python)                     (tb_golden_compare)
```

Test cases are generated **directly as integers** in Python. Deriving them by narrowing FP32 values would leave gaps at the boundaries, since symmetric scaling means the minimum value (e.g. −8 at INT4) never appears. The case mix is 5 sparse / 5 boundary / 5 random, where the boundary cases combine the extremes of each precision (INT4: −8/+7, INT8: −128/+127, INT16: −32768/+32767).

Golden values are computed in NumPy, fully independent of the DUT. Computing the golden reference inside Verilog would allow the same bug to propagate into both sides and render the check meaningless.

**Result:** 15 cases × 16 elements = **240/240 bit-exact matches** across all six configurations.

### ② Precision loss (SQNR)

**Question:** how far does narrowing the data width move the result away from FP32?

```
SQNR = 10 · log₁₀ ( Σx² / Σ(x − x̂)² )   [dB]
```

where `x` is the FP32 original and `x̂` is the value after narrowing and rescaling back.

```
shared FP32 source → round() to target precision → integer matmul → rescale → compare to FP32
```

**Why FP32 is the reference:**

1. Accuracy is always relative to a reference, so an un-narrowed common ground truth is required.
2. FP32 carries roughly 24 significant bits — at least 8 more than the widest case under test (INT16) — so the error of the ruler itself is negligible.
3. Neural networks are trained in FP32, so in practice "accuracy loss" *means* deviation from the FP32 model.

Using INT8 as the reference would make INT16's advantage unmeasurable: widening cannot recreate information the source never had.

### How the two connect

Verification ① established that hardware output matches NumPy integer results bit for bit. Therefore SQNR — which applies the same scaling to the same integers — is equally valid whether computed in Python or in hardware. **Without verification ①, the SQNR numbers would be a pure software simulation with no bearing on the hardware.**

Integer multiplication is bit-exact by construction, so passing verification ① in every configuration is the expected outcome, not a finding. Precision loss occurs earlier, at the rounding step, not in the multiplier.

---

## Measurement Methodology

| Metric | Conditions | Tool |
|---|---|---|
| Resources (LUT/CARRY4/FF/Slice) | 10 ns constraint, post-implementation | `report_utilization` |
| Timing | 10 ns constraint, back-calculated from WNS | `report_timing_summary` |
| Dynamic power | Post-Implementation Timing Simulation → SAIF | `read_saif` → `report_power` |

**Power measurement procedure.** Toggle activity over a 20 µs window is captured to SAIF during Post-Implementation Timing Simulation, then read back into the Implemented Design to compute power. All six configurations achieved Confidence Level *High* with 64–70% net matching.

Post-Synthesis Functional Simulation was rejected: with zero routing delay it misses glitch power, measuring 2 mW low on an identical design (INT16 Wallace) compared to Post-Implementation Timing. All configurations therefore use the Post-Implementation Timing flow.

---

## Analysis

### The Wallace tree's advantage depends on data width

Area, speed, and power all move monotonically in the same direction as width increases — evidence of a structural trend rather than measurement coincidence.

**At INT4 the Wallace tree loses on every metric.** The cause is partial-product count. Wallace-tree gains come from compressing many partial products through a CSA tree, but a 4-bit multiply produces only four — too few to compress meaningfully. Identical CARRY4 usage (68 in both) confirms this: no reduction whatsoever, while the CSA structure's intermediate sum/carry routing overhead is added on top.

**The crossover occurs at INT8 and widens at INT16.** Fmax in particular flips sign: −9.9% at INT4, −1.6% at INT8, **+3.4%** at INT16. In other words, **there is a minimum viable data width for the Wallace tree**, and under these experimental conditions that boundary lies between 4 and 8 bits.

### The mechanism differs by width

"Wallace wins" means something different at INT8 than at INT16.

| | INT8 | INT16 |
|---|---|---|
| CARRY4 | 132 → 52 (**−60.6%**) | 180 → 180 (unchanged) |
| LUT | 781 → 779 (unchanged) | 917 → 829 (**−9.6%**) |
| Slice | 285 → 261 (−8.4%) | 329 → 276 (−16.1%) |

**INT8 — improved placement density.** LUT count is unchanged, yet slices drop 8.4%. Carry chains must be placed in vertically contiguous slices, which constrains placement freedom; using 60% fewer CARRY4 primitives lets the placer pack LUTs more tightly. Measured LUTs-per-slice rose from 2.74 to 2.98.

**INT16 — less logic outright.** CARRY4 usage is identical, but 88 LUTs disappear. At 16 bits the final adder is wide enough that the carry chain is needed regardless; compressing 16 partial products through the CSA tree reduces the combinational logic itself.

So the source of the gain is **placement efficiency** at narrow widths and **logic volume** at wide ones.

### Dedicated carry chains cancel the speed advantage

The near-zero Fmax difference at INT8 (−1.6%) is an FPGA architecture artifact. Per-stage delays extracted from the timing report:

| Path | Delay per stage |
|---|---|
| CARRY4 (dedicated carry chain) | ≈ 0.11 ns |
| LUT path | ≈ 0.31 ns |

Xilinx 7-series provides a dedicated carry chain as a hard macro in every slice, roughly 3× faster than a LUT path. A Wallace tree implements its CSA tree in LUTs, so even though it reduces carry-propagation stages, slower LUTs fill the vacated space and the gain is cancelled.

On an ASIC, where only gate delay exists, tree depth translates directly into speed. On an FPGA, vendor-provided hard logic favors the array multiplier — and the narrower the data width, the more dominant that effect.

**INT16 reverses this.** The carry-propagation chain in a 16-bit array multiplier grows long enough that the tree-depth difference (roughly 12 stages) outweighs the CARRY4 speed advantage. That INT16 Array is the only configuration to miss the 10 ns constraint (WNS −0.086) follows from the same mechanism.

### Cost/accuracy exchange rate

| Transition (Array) | SQNR | LUT | Slice | Dynamic |
|---|---|---|---|---|
| INT8 → INT4 | −25.2 dB | −38.7% | −40.0% | −40% |
| INT8 → INT16 | +48.3 dB | +17% | +15% | +20% |

Moving from INT8 to INT4 costs 25 dB of precision — roughly a 330× increase in noise power, or a jump in relative error from about 1.2% to 23%. In exchange, resources and power drop by about 40%.

Measured SQNR agrees well with theory. Uniform rounding improves SQNR by 6.02 dB per bit, predicting a 24.1 dB loss for four bits removed; the measurement was 25.2 dB. This agreement is itself evidence that the precision-narrowing implementation is sound.

Resource scaling, however, is far gentler than the analytical prediction (multiplier area ∝ width², i.e. 4×). INT8 → INT16 grows only 15–20%. This is attributable to width-linear and width-invariant components — the accumulator, control FSM, and LFSR — plus synthesis removing unused upper accumulator bits. FF count barely moving (426 → 429) supports this reading.

### Independence of the two axes

Multiplier structure does not affect accuracy. Array and Wallace tree differ only in the order in which partial products are summed, and integer addition is associative, so results are bit-identical. Verification ① confirmed this empirically.

| Axis | Trade-off | Decision criterion |
|---|---|---|
| Data width | accuracy ↔ cost | consider SQNR and resources together |
| Multiplier structure | none (accuracy identical) | compare cost only |

Choosing a multiplier is therefore a pure cost reduction with no accuracy penalty — a net win whenever the conditions are right. As established above, those conditions depend on data width.

---

## Limitations

**Timing measurement.** Fmax is back-calculated from WNS, mostly under timing-met conditions at a 10 ns constraint. The tool stops optimizing once a constraint is satisfied, so these values reflect *slack against a given constraint*, not the physical limit of the design. A separate experiment tightening the constraint to 3 ns raised INT8 Array's Fmax from 105.0 MHz to 113.8 MHz. Relative comparison between configurations remains valid since conditions are identical, but the absolute values should not be read as design limits.

**Power measurement resolution.** At 4×4 scale, dynamic power falls in the 6–12 mW range, and Vivado's mW-level rounding makes a 1 mW difference indistinguishable from measurement error. INT8's 10 vs. 9 mW sits within that resolution limit; INT16's 12 vs. 10 mW is judged significant because every sub-category (Clocks, Slice Logic, Signals) is consistently lower.

**Placement dependence.** Chip utilization is only 1–2%, giving the placer little incentive to pack logic tightly. Routing delay accounted for 51% of INT8 Array's critical path, meaning structural differences may be partially masked by placement variance.

**Scope of SQNR.** SQNR measures precision loss at the arithmetic level; its quantitative link to actual neural network task accuracy (classification rate, etc.) was not verified. Only symmetric per-tensor scaling was measured — per-channel scaling could recover a substantial portion of INT4's loss. The normally-distributed random matrices used here also differ from real network weight distributions.

**Threshold precision.** The Wallace tree's minimum viable width was localized to between 4 and 8 bits, but INT5/6/7 were not measured, so the exact boundary remains unidentified.

---

## Future Work

| | Item | Approach |
|---|---|---|
| ① | Pin down the Wallace-tree threshold width | Measure INT5/6/7 to refine the crossover point |
| ② | Independent Fmax measurement | Tighten constraints into timing failure to find the physical limit |
| ③ | Per-channel scaling SQNR | Quantify how much INT4 precision is recovered |
| ④ | Scale up the array | Re-verify trends at 8×8 and beyond, easing the power resolution problem |

---

## Repository Structure

```
systolic-matmul-fpga/
├── rtl/
│   ├── rtl_int4/        # INT4 RTL (array, wallace, wrapper, top)
│   ├── rtl_int8/        # INT8 RTL
│   └── rtl_int16/       # INT16 RTL
├── tb/
│   ├── tb_int4/         # INT4 testbenches
│   ├── tb_int8/         # INT8 testbenches
│   └── tb_int16/        # INT16 testbenches
├── constraints/         # XDC constraints (clock, pin assignment)
├── mem/                 # verification .mem files (A / B / C_golden)
├── precision_py/        # precision_eval.py — .mem generation and SQNR measurement
├── result/              # raw measurement reports
└── docs/                # weekly reports, presentation material
```

---

## Getting Started

### Requirements

- Xilinx Vivado 2025.2 (or later)
- Icarus Verilog
- Python 3 with NumPy
- Digilent Nexys A7-100T (for board-level verification only)

### 1. Generate verification data and evaluate precision

```bash
python precision_py/precision_eval.py
# → writes INT4/8/16 .mem files and prints the SQNR report
```

### 2. RTL simulation

```bash
# multiplier-level check
iverilog -o sim.out tb/tb_int8/tb_MatMult.v rtl/rtl_int8/arrayMatMult.v && vvp sim.out

# system-level golden comparison
iverilog -o sim.out tb/tb_int8/tb_golden_compare.v rtl/rtl_int8/arrayMatMult.v && vvp sim.out
```

### 3. Vivado measurement

1. Add the sources for the chosen precision from `rtl/rtl_int*/` plus the XDC files in `constraints/`.
2. Set the top module — `power_bench_wrapper` for resource/power measurement, `fpga_top_bram` for board verification.
3. Run Synthesis → Implementation with a 10 ns constraint.
4. Read LUT / CARRY4 / FF / Slice from `report_utilization`.
5. For power, run Post-Implementation Timing Simulation, generate SAIF, then `read_saif` → `report_power`.

```tcl
# simulator console
restart
open_saif <path>/power_int8_array.saif
log_saif [get_objects -r /tb_power_bench/dut/*]
run 20us
close_saif

# Implemented Design console
read_saif <path>/power_int8_array.saif
report_power
```

> **Note:** keep SAIF filenames separated by precision and structure, and confirm Confidence Level *High* with net matching above 60% in the resulting report. The wrapper instance name in the testbench differs per precision (`power_bench_wrapper_INT4`, etc.), so verify it whenever switching projects.

---

## Authors

**2026 Summer URP (Undergraduate Research Program)**
Department of Semiconductor Systems Engineering, Sungkyunkwan University
Advisor: Prof. Yulhwa Kim

Jayden Bae · Aiden Lee · Steven Ju · Jaehyeon Lee
