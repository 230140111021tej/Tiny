# Technical Report: TinyCNN FPGA Edge AI for MNIST Classification

**Target platform:** Digilent Basys 3 / Xilinx Artix-7 XC7A35T-1CPG236
**FPGA toolchain:** Vivado 2025.1
**Implementation baseline:** V7
**Dataset:** MNIST test set
**Status:** Engineering implementation and recorded hardware validation

---

## Abstract

This project implements a compact quantized convolutional neural network (TinyCNN) for handwritten-digit classification on a resource-constrained FPGA. The target is the Digilent Basys 3 board containing a Xilinx Artix-7 XC7A35T device. The documented network uses a 3 × 3 convolution with four filters, ReLU activation, 2 × 2 max pooling, and a fully connected layer producing ten class scores.

The implementation uses signed 8-bit weights, unsigned 8-bit activations, signed 32-bit accumulators, and fixed-point requantization. The recorded validation procedure sent 10,000 MNIST images through a UART-based hardware test setup. It received 9,999 predictions, of which 9,465 were correct and 534 were incorrect. One image attempt did not return a response. Accuracy among received predictions was 94.66%; correct predictions divided by all attempts was 94.65%.

The final routed V7 reports show 1,986 slice LUTs, 851 slice registers, two block RAM tiles, and one DSP slice used. The implementation met the documented 100 MHz timing constraint. Vivado estimated total on-chip power at 0.110 W with medium confidence. This is a tool estimate, not a physical board-power measurement.

This report documents the recorded implementation and its limitations. It does not establish research novelty or superiority over CPU or GPU implementations.

## 1. Objectives

The project objectives are:

1. Implement a compact CNN inference pipeline using fixed-point arithmetic.
2. deploy the design on the Basys 3 FPGA.
3. Support image classification through the recorded UART test interface.
4. Evaluate classification behavior using the MNIST test dataset.
5. Compare FPGA predictions with floating-point and integer software references.
6. Record final routed resource utilization and timing results.
7. Preserve reproducible artifacts and identify opportunities for further experimentation.

## 2. System overview

The documented system combines a host-side validation environment, an FPGA implementation, and stored validation and implementation reports.

The host-side tools export MNIST images, transmit image data through UART, collect predictions, and compare predictions against known labels. Vivado reports provide the final routed implementation metrics.

### 2.1 Hardware and toolchain

| Item | Configuration |
|---|---|
| Development board | Digilent Basys 3 |
| FPGA | Xilinx Artix-7 XC7A35T-1CPG236 |
| FPGA tools | Vivado 2025.1 |
| Main clock constraint | 100 MHz |
| Clock period | 10 ns |
| Host environment | Windows |
| Python interpreter used in recorded workflow | `C:\Python312\python.exe` |
| UART baud rate | 115200 |
| UART framing | 8-N-1 |

The recorded UART port was COM4. The actual port may differ on another computer.

### 2.2 Data interface

The documented request packet contains:

| Field | Size |
|---|---:|
| Synchronization prefix | `A5 5A` (2 bytes) |
| Grayscale image payload | 784 bytes |
| Total request | 786 bytes |
| Prediction response | One class byte |

The image is 28 × 28 pixels. Each pixel is represented by an unsigned 8-bit value. The returned class represents one of the ten MNIST digits.

The packet format and observed behavior are documented in the validation methodology. The complete UART top-level RTL was not included in the source inspection used to prepare this report, so detailed UART state-machine behavior is not asserted here.

## 3. CNN architecture

The model summary identifies the architecture as:

`Conv3x3_1to4_ReLU_MaxPool2x2_FC676to10`

![TinyCNN inference architecture](figures/tinycnn_architecture.png)

### 3.1 Input

Each input image has dimensions 28 × 28 and contains 784 unsigned 8-bit pixels.

### 3.2 Convolution

The convolution uses a 3 × 3 kernel, one input channel, and four output filters. With valid convolution and no spatial padding, the output dimensions are:

\[
(28-3+1)\times(28-3+1)\times4
=26\times26\times4
\]

The RTL declares 36 signed 8-bit convolution weights and four signed 32-bit convolution biases.

### 3.3 ReLU and requantization

Negative convolution accumulations are clamped to zero. The RTL then applies a fixed-point scaling operation using the recorded multiplier and shift:

- Multiplier: 54688
- Shift: 24

The result is saturated to the unsigned 8-bit range.

The model summary records the convolution weight scale as approximately 0.0103445 and the activation scale as approximately 0.012445. These scales are metadata from the recorded model configuration; their exact mapping to every arithmetic operation should be confirmed against the complete quantization implementation before making bit-exact equivalence claims.

### 3.4 Max pooling

The design performs 2 × 2 max pooling with stride 2. The feature-map dimensions become:

\[
13\times13\times4=676
\]

The pooled features are stored as unsigned 8-bit values.

### 3.5 Fully connected layer

The fully connected layer maps 676 features to ten output classes. The RTL declares 6,760 signed 8-bit weights and ten signed 32-bit biases.

The core maintains ten signed 32-bit class scores. The class with the largest score is intended to represent the predicted digit; the precise final class-selection and output-transfer logic belongs to the surrounding integration and is not shown in the reviewed core module.

## 4. RTL implementation

The reviewed source file is:

`rtl/tinycnn_core.v`

It declares five control states:

| State | Function |
|---|---|
| `IDLE` | Wait for a start request |
| `CONV` | Compute convolution outputs and apply activation and scaling |
| `POOL` | Compute pooled features |
| `FC` | Accumulate fully connected class scores |
| `DONE` | Signal completion and return to idle |

The module exposes a clock, reset, start signal, busy and done flags, and ten signed 32-bit scores.

The reviewed core source also contains initialization-time `$readmemh` statements for an image, convolution weights and biases, and fully connected weights and biases. These paths are specific to the recorded development environment. A portable release should verify the intended memory initialization and image-input path for the complete deployed design.

The reviewed core alone does not establish how the UART receiver writes incoming pixels into the CNN input buffer. The full top-level RTL and integration constraints should be included in the final reproducibility package.

## 5. Fixed-point arithmetic

The model uses the following numerical representations:

| Quantity | Representation |
|---|---|
| Input pixels | Unsigned 8-bit |
| Convolution weights | Signed INT8 |
| Fully connected weights | Signed INT8 |
| Activations | Unsigned 8-bit |
| Accumulators | Signed INT32 |
| Class scores | Signed INT32 |
| Convolution requantization multiplier | 54688 |
| Convolution requantization shift | 24 |

The model summary also records the fully connected weight scale as approximately 0.00576368.

Fixed-point arithmetic reduces the width of stored weights and activations compared with conventional floating-point representations. However, the hardware cost and accuracy consequences depend on the complete implementation, including multiplier mapping, accumulator widths, saturation, rounding, memory inference, and synthesis decisions.

A future bit-exact verification should compare intermediate convolution outputs, pooled activations, and final class scores against a reference implementation using the same weights and arithmetic rules.

## 6. Validation methodology

The validation procedure is documented in `validation_methodology.md`.

The recorded process consists of exporting the MNIST test images, programming the known V7 bitstream, transmitting images through the UART test setup, collecting returned predictions, and comparing the results with the image labels.

The host-side tester records per-image outcomes, including prediction status and communication errors. Original results are retained as CSV and JSON artifacts.

### 6.1 Recorded full-test result

Source CSV:

`validation/results/mnist10000_results_20261020_122444.csv`

Source summary:

`validation/results/mnist10000_summary_20261020_122444.json`

![Full MNIST validation summary](figures/mnist_validation_summary.png)

| Metric | Recorded value |
|---|---:|
| Attempts | 10,000 |
| Responses received | 9,999 |
| Correct predictions | 9,465 |
| Incorrect received predictions | 534 |
| Missing responses | 1 |
| Accuracy among received responses | 94.66% |
| Correct predictions / all attempts | 94.65% |

The denominators must be kept distinct:

\[
\frac{9465}{9999}\times100\approx94.66\%
\]

\[
\frac{9465}{10000}\times100=94.65\%
\]

The missing response is a communication outcome and is not included among received classifications.

### 6.2 Confusion matrix

![Confusion matrix](figures/confusion_matrix.png)

The confusion matrix contains 9,465 diagonal entries representing correct classifications and 534 off-diagonal entries representing incorrect classifications. Its total is 9,999 received predictions.

The recorded missing response occurred at MNIST index 7449, whose true label was digit 0. That attempt is excluded from the received-prediction confusion matrix.

### 6.3 Per-digit accuracy

![Per-digit accuracy](figures/per_digit_accuracy.png)

Per-digit accuracy is calculated from the received predictions for each true label. Consequently, the digit 0 denominator is one smaller than its number of attempted images because the missing response had true label 0.

Per-digit values are useful for identifying classes that merit additional error analysis. They do not, by themselves, explain the cause of a misclassification.

## 7. Software-reference comparison

The recorded comparison reports:

| Implementation | Accuracy |
|---|---:|
| Floating-point software reference | 94.65% |
| Integer software reference | 94.67% |
| FPGA, among received responses | 94.66% |

The FPGA and integer-reference predictions agreed on 9,998 of 9,999 received samples, or approximately 99.99%.

This agreement is evidence of close output correspondence on the recorded test set. It does not prove that all intermediate arithmetic or stored weights are bit-identical.

The software comparison helper was recorded at:

`D:\FPGA_EdgeAI\cnn_baseline\scripts\compare_tinycnn_mnist100.py`

Reproduction requires checking the helper's configuration, checkpoint, quantization settings, dataset, and input CSV. The reference accuracies should not be treated as a controlled comparison with a CPU or GPU performance baseline.

## 8. Routed FPGA implementation results

The following values are taken from the final routed V7 implementation reports. They should not be mixed with results from earlier optimization versions.

![V7 FPGA resource utilization](figures/resource_utilization.png)

### 8.1 Resource utilization

| Resource | Used | Capacity | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 1,986 | 20,800 | 9.55% |
| Slice registers | 851 | 41,600 | 2.05% |
| Block RAM tiles | 2 | 50 | 4.00% |
| DSP slices | 1 | 90 | 1.11% |

These figures describe the recorded routed implementation on the specified FPGA. They do not establish that all alternative implementations would have the same resource use.

### 8.2 Timing results

| Metric | Result |
|---|---:|
| Clock period constraint | 10.000 ns |
| Clock frequency constraint | 100 MHz |
| Worst negative slack (WNS) | +0.272 ns |
| Total negative slack (TNS) | 0 ns |
| Worst hold slack (WHS) | +0.072 ns |
| Total hold slack (THS) | 0 ns |

The recorded routed timing report states that all user-specified timing constraints are met.

Meeting the 100 MHz constraint does not, by itself, establish the end-to-end time required to classify an image. The controller's cycle count, UART transmission time, and host-side overhead must be measured separately.

### 8.3 Power estimate

| Metric | Vivado estimate |
|---|---:|
| Total on-chip power | 0.110 W |
| Dynamic power | 0.038 W |
| Device static power | 0.072 W |
| Confidence | Medium |

These values are Vivado estimates. They are not direct measurements of the Basys 3 board's physical power consumption.

A board-level power claim requires a documented measurement procedure, including the measurement point, operating conditions, workload, and treatment of idle and active power.

### 8.4 Report locations

The final V7 reports are preserved in the project tree. The project also contains the following summary documents:

- `reports/v7/routed_timing.rpt`
- `reports/v7/routed_utilization.rpt`
- `reports/v7/routed_power.rpt`
- `docs/implementation_results.md`

The exact report paths should be checked when moving the project to another environment.

## 9. Reproducibility

The project includes scripts for exporting MNIST images, training/exporting the TinyCNN model, generating figures, and running UART batch tests.

The documented full-test workflow uses Python 3.12 and PowerShell. The recorded hardware test uses COM4 at 115200 baud, but another host may assign a different port.

The principal validation artifacts are the timestamped CSV and JSON files listed in Section 6. They should be retained unchanged when preparing a release.

For a reproducible publication, the following should be documented and versioned where appropriate:

1. Exact model checkpoint and exported weights.
2. Quantization parameters and arithmetic rules.
3. ROM contents and initialization paths.
4. Full RTL hierarchy, including UART and board integration.
5. Vivado project configuration, constraints, and version.
6. Host-side scripts and Python dependencies.
7. Dataset export procedure and manifest.
8. Validation CSV and summary JSON.
9. Final routed timing, utilization, and power reports.
10. Any changes between the V7 baseline and later experiments.

Generated build directories should be reviewed before publication. Large, redundant, machine-specific, or reproducible generated files should not automatically be committed merely because they exist locally.

## 10. Limitations

The current evidence has several limitations:

- One response was missing in the recorded 10,000-attempt run.
- UART round-trip time includes communication and host-side overhead; it is not a direct measure of pure FPGA inference latency.
- Vivado's 0.110 W result is an estimate rather than a board-level power measurement.
- The reviewed CNN core source does not, by itself, document the complete UART-to-classification top-level integration.
- Software-reference agreement does not prove complete bit-exact equivalence.
- The recorded results apply to this model, dataset, bitstream, and validation setup.
- No controlled CPU/GPU benchmark is provided.
- No literature review has yet established a novel research contribution.

These limitations should remain visible in technical presentations and any later paper draft.

## 11. Proposed future experiments

The existing research plan proposes investigating how fixed-point quantization affects classification accuracy and FPGA resource and timing cost.

A controlled experimental sequence is:

1. Freeze the validated V7 RTL, bitstream, model/ROM, configuration, scripts, and original results.
2. Record the baseline metrics and tool settings.
3. Select one quantization variable to change per experiment.
4. Keep the dataset, preprocessing, and evaluation method fixed.
5. Evaluate software accuracy before committing a variant to hardware.
6. Run hardware validation and record missing responses separately.
7. Compare classification accuracy, LUTs, registers, BRAM, DSP, timing, and clearly defined latency.
8. Repeat experiments where practical and retain failures and variability.
9. Measure physical board power if an energy-efficiency claim is intended.
10. Review related literature before making novelty claims.

Each experimental variant should have its own configuration, results, and implementation reports. The original V7 baseline should remain available for comparison.

## 12. Conclusion

The recorded project demonstrates a quantized TinyCNN implementation evaluated on a physical Basys 3 FPGA. In the recorded full-dataset run, 9,465 of 9,999 received predictions were correct, yielding 94.66% accuracy among received predictions. One of the 10,000 attempts did not return a response.

The final routed implementation used 9.55% of the device's slice LUT capacity, 2.05% of its slice register capacity, 4.00% of its block RAM tile capacity, and 1.11% of its DSP slice capacity. The routed report states that the 100 MHz timing constraints were met.

The power figure of 0.110 W remains a medium-confidence Vivado estimate. Further work should focus on complete integration documentation, bit-exact verification, controlled quantization experiments, clearly separated latency measurements, and a documented physical power measurement if required.

The current results support an engineering implementation claim. Additional controlled experiments and related-work analysis are needed before claiming research novelty or superiority over alternative platforms.

---

## References and project artifacts

This report is based on the project's own recorded artifacts:

- `reports/model_summary.json`
- `docs/implementation_results.md`
- `docs/validation_methodology.md`
- `docs/research_plan.md`
- `rtl/tinycnn_core.v`
- `validation/results/mnist10000_results_20261020_122444.csv`
- `validation/results/mnist10000_summary_20261020_122444.json`
- `reports/v7/routed_timing.rpt`
- `reports/v7/routed_utilization.rpt`
- `reports/v7/routed_power.rpt`

External literature references have not yet been added. They should be selected and verified during the literature-review phase rather than invented or cited without inspection.
