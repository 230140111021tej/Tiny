# V7 FPGA Implementation Results

Target: Digilent Basys 3, Xilinx Artix-7 XC7A35T-1CPG236. Tool: Vivado 2025.1. Clock constraint: 100 MHz (10 ns).

## Routed resource utilization

| Resource | Used | Capacity | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 1,986 | 20,800 | 9.55% |
| Slice registers | 851 | 41,600 | 2.05% |
| Block RAM tiles | 2 | 50 | 4.00% |
| DSP slices | 1 | 90 | 1.11% |

## Routed timing

| Metric | Result |
|---|---:|
| WNS | +0.272 ns |
| TNS | 0 ns |
| WHS | +0.072 ns |
| THS | 0 ns |
| Clock period | 10 ns |
| Clock frequency constraint | 100 MHz |

The routed timing report states that all user-specified timing constraints are met.

## Power estimate

| Metric | Vivado estimate |
|---|---:|
| Total on-chip power | 0.110 W |
| Dynamic power | 0.038 W |
| Device static power | 0.072 W |
| Confidence | Medium |

These are tool estimates, not direct measurements of board power.

## Full-dataset validation

- Attempts: 10,000
- Responses received: 9,999
- Correct predictions: 9,465
- Misclassified received images: 534
- Missing responses: 1
- Accuracy among responses: 94.66%
- Correct predictions / all attempts: 94.65%

Software comparison: floating-point reference 94.65%, integer reference 94.67%, FPGA 94.66%. FPGA and integer-reference predictions agreed on 9,998 of 9,999 received samples.

Primary files: `validation/results/mnist10000_results_20261020_122444.csv` and `validation/results/mnist10000_summary_20261020_122444.json`.

Do not mix these figures with reports from earlier optimization versions.
