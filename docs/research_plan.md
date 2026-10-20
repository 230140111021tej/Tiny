# Research Plan: Quantized TinyCNN on a Resource-Constrained FPGA

## 1. Current contribution and research status

The current project implements a quantized CNN on a physical Basys 3 FPGA, with UART input/output, a recorded 10,000-attempt MNIST evaluation, software-reference comparison, and routed Vivado reports.

The existing V7 implementation is the frozen baseline. Its measured results are implementation evidence, not proof of research novelty. The experiments below are proposed work and must not be reported as completed until the corresponding runs and checks have been performed.

## 2. Research question

**How do fixed-point quantization choices affect classification accuracy, FPGA resource utilization, timing, and inference latency for a small CNN on an Artix-7 FPGA?**

Refine this question after reviewing relevant literature and identifying a specific research gap.

## 3. Frozen baseline

Before modifying the design, preserve and identify:

- V7 RTL source and its version identifier.
- The exact programmed bitstream and its generation reports.
- Model weights, biases, ROM files, and quantization parameters.
- Dataset split, input preprocessing, and software-reference implementation.
- UART protocol, test scripts, tool versions, and clock constraints.
- Original per-image CSV and summary JSON results.

Record file hashes where practical. Do not overwrite the original baseline results with results from experimental variants.

### Recorded baseline metrics

| Metric | Recorded value | Interpretation |
|---|---:|---|
| Test attempts | 10,000 | Total attempted evaluations |
| Responses received | 9,999 | One response was missing |
| Correct predictions | 9,465 | Correct received responses |
| Accuracy among received responses | 94.66% | 9,465 / 9,999 |
| Correct predictions / all attempts | 94.65% | 9,465 / 10,000 |
| LUT utilization | 1,986 / 20,800 (9.55%) | Routed V7 report |
| Register utilization | 851 / 41,600 (2.05%) | Routed V7 report |
| BRAM tiles | 2 / 50 (4%) | Routed V7 report |
| DSP utilization | 1 / 90 (1.11%) | Routed V7 report |
| Worst negative slack | +0.272 ns WNS | Reported timing result |
| Estimated total power | 0.110 W | Vivado estimate, not a board measurement |

Use the original reports and result files as the authoritative record. Preserve the missing response as a separate reliability metric.

## 4. Controlled experiment matrix

Each experiment is proposed. Complete one controlled change at a time and retain the baseline configuration for comparison.

| ID | Experiment | Single main variable | Required measurements |
|---|---|---|---|
| E0 | Frozen V7 baseline | None | Accuracy, response rate, resources, timing, latency |
| E1 | Convolution quantization | Convolution weight or activation precision/scale | Accuracy, errors, resources, timing |
| E2 | Fully connected quantization | FC weight precision or scale | Accuracy, errors, resources, timing |
| E3 | Accumulator implementation | Accumulator width, with overflow behavior documented | Accuracy, overflow evidence, resources, timing |
| E4 | Arithmetic implementation | One documented multiplier or scaling implementation | Accuracy, DSP/LUT use, timing |
| E5 | UART and inference timing | Measurement method or transfer configuration, without changing CNN arithmetic | Transfer time, compute time if separately measurable, end-to-end latency |

Do not combine multiple changes in one experiment unless it is explicitly designated as a later combined experiment. Keep preprocessing, dataset split, class ordering, and test procedure constant.

Before each run, document the exact configuration and verify that the intended variant was synthesized and programmed.

## 5. Measurement protocol

For every baseline or experimental run:

1. Record the RTL/configuration identifier, source revision, model and ROM hashes, tool version, and relevant constraints.
2. Run the software reference using the same input representation and dataset split.
3. Run hardware validation with a fixed, documented test set and protocol.
4. Save per-image predictions, labels, response status, and errors.
5. Report attempted images, received responses, correct predictions, missing responses, and accuracy using explicit denominators.
6. Generate a confusion matrix and per-class accuracy from received responses, while separately reporting missing responses.
7. Record LUTs, registers, BRAM, DSP, WNS, TNS, and the relevant timing constraints from implementation reports.
8. Define latency boundaries. Separate UART transfer and response overhead from CNN compute latency wherever the implementation permits reliable measurement.
9. Record power methodology and tool settings. Treat Vivado power analysis as an estimate; do not describe it as a physical board measurement.
10. Repeat runs where practical and preserve failures instead of silently discarding them.

## 6. Acceptance criteria

A run is suitable for comparison only when the following checks are satisfied:

- **Configuration:** The tested RTL, weights, quantization settings, bitstream, and constraints are identified.
- **Dataset:** The same documented test set and preprocessing are used across compared variants.
- **Accounting:** Every attempted sample has a recorded outcome; missing responses are not counted as correct predictions.
- **Reproducibility:** Output files and logs are saved, and reported metrics can be recomputed from the raw results.
- **Synthesis and timing:** Resource figures come from the identified implementation run, with timing constraints stated.
- **Fair comparison:** The intended experimental variable is the main change; other relevant settings remain fixed.
- **Claims:** Any claim about improvement is supported by the recorded measurements and their limitations.

A failed criterion means the run must be investigated or labelled incomplete before drawing a conclusion. Do not invent a target accuracy or resource improvement before the baseline and literature review justify it.

## 7. Results table template

Complete one row for each experiment. Use "Not measured" rather than guessing missing values.

| ID | Configuration | Attempts | Responses | Correct | Accuracy among responses | LUT | Registers | BRAM | DSP | WNS (ns) | Latency method/result | Notes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| E0 | V7 baseline | 10,000 | 9,999 | 9,465 | 94.66% | 1,986 | 851 | 2 | 1 | +0.272 | Record/verify method | One missing response |
| E1 | Pending | — | — | — | Not measured | — | — | — | — | — | Not measured | Proposed |
| E2 | Pending | — | — | — | Not measured | — | — | — | — | — | Not measured | Proposed |
| E3 | Pending | — | — | — | Not measured | — | — | — | — | — | Not measured | Proposed |
| E4 | Pending | — | — | — | Not measured | — | — | — | — | — | Not measured | Proposed |

## 8. Literature review and novelty

Review relevant work on quantized CNN inference, FPGA-based neural networks, fixed-point arithmetic, and resource-constrained implementations. For each relevant work, record its architecture, numeric format, target hardware, evaluation dataset, reported accuracy, resource use, timing, and limitations.

Identify a specific gap before claiming novelty. A physical FPGA implementation and a large test run demonstrate engineering work, but do not alone establish a novel research contribution.

## 9. Evidence required for a paper

- Related-work review and a clearly defined research gap.
- Architecture and fixed-point arithmetic description.
- Reproducible hardware/software setup.
- Controlled experiments against the frozen baseline.
- Per-class accuracy and error analysis.
- Routed resource and timing reports.
- Clearly defined latency measurements.
- Documented board-level power measurements if energy or power efficiency is claimed.
- Limitations, raw result artifacts, and sufficient instructions to reproduce the evaluation.

## 10. Limitations and claim discipline

- The current evaluation includes one missing hardware response.
- End-to-end UART time is not equivalent to CNN compute latency.
- Vivado-estimated power is not a physical board measurement.
- Software-reference agreement does not independently prove correctness of every implementation detail.
- No CPU/GPU superiority, energy-efficiency advantage, or research novelty should be claimed without suitable evidence.

## 11. Immediate next steps

1. Preserve the V7 baseline and original validation files.
2. Complete the repository audit and publish the documented baseline.
3. Review related literature and refine the research question.
4. Select one quantization variable for the first controlled experiment.
5. Define the exact configuration and measurement procedure before running that experiment.
6. Add results only after the run has completed and its raw data has been checked.

## Conclusion

The current V7 project provides a documented baseline for future controlled experiments. The next research phase should evaluate specific quantization and arithmetic choices without compromising the baseline or overstating what the current evidence establishes.
