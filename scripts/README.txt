# TinyCNN FPGA Validation Guide

Project root:
D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn

## Hardware and tools

- Board: Digilent Basys 3
- FPGA: XC7A35T-1CPG236
- Vivado: 2025.1
- Host Python: C:\Python312\python.exe
- UART: 115200 baud, 8-N-1
- Current recorded port: COM4

Use the COM port assigned to your own board.

## 1. Export MNIST validation images

Exporter:
scripts\export_mnist_validation.py

The exporter uses the existing MNIST IDX dataset under:
D:\FPGA_EdgeAI\cnn_baseline\data\MNIST\raw

To export the full test set:

& "C:\Python312\python.exe" "D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn\scripts\export_mnist_validation.py" --count 10000

The recorded full-test dataset is:
validation\mnist10000

It contains the exported images and manifest. Exporting data does not retrain the model or change the FPGA bitstream.

## 2. Run a short hardware test

Ensure the correct bitstream is programmed and the Basys 3 is connected.

Example:

& "D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn\scripts\run_uart_batch_test.ps1" -Dataset mnist10 -PortName COM4 -BaudRate 115200

Use a short test to confirm communication before running a large batch.

## 3. Run the full validation

& "D:\FPGA_EdgeAI\cnn_baseline\tiny_cnn\scripts\run_uart_batch_test.ps1" -Dataset mnist10000 -PortName COM4 -BaudRate 115200

The script writes a per-image CSV and a summary JSON under:
validation\results

Do not overwrite the recorded result when preparing documentation. A new run creates a new timestamped result.

## 4. Recorded full-test result

Source CSV:
validation\results\mnist10000_results_20261020_122444.csv

Source summary:
validation\results\mnist10000_summary_20261020_122444.json

- Attempts: 10,000
- Responses received: 9,999
- Correct predictions: 9,465
- Misclassified received images: 534
- Missing responses: 1
- Accuracy among received responses: 94.66%
- Correct predictions divided by all attempts: 94.65%

Keep classification errors separate from missing UART responses.

## 5. Software comparison

Comparison script:
scripts\compare_tinycnn_mnist100.py

Recorded comparison:
- Floating-point reference: 94.65%
- Integer reference: 94.67%
- FPGA on received responses: 94.66%
- Integer-reference/FPGA agreement: 9,998 of 9,999 responses

The comparison script and its configuration should be checked before reproducing the comparison, so that the same model checkpoint, quantization settings, dataset, and CSV are used.

## 6. Timing, resources, and power

Use the V7 routed implementation reports for published hardware figures.

- Routed timing: uart_work\counter_opt_v7\vivado_build\requant_pipeline_v7\v7_routed_timing.rpt
- Routed utilization: uart_work\counter_opt_v7\vivado_build\requant_pipeline_v7\v7_routed_utilization.rpt
- Routed power: uart_work\counter_opt_v7\vivado_build\requant_pipeline_v7\project_v7\tinycnn_uart_v7.runs\impl_1\tinycnn_uart_top_power_routed.rpt

The power report is a medium-confidence Vivado estimate, not a direct physical measurement.

UART round-trip time includes communication and host overhead; it must not be reported as pure FPGA inference latency.

## 7. Important safeguards

- Preserve the known-good V7 bitstream and RTL.
- Do not mix V7 routed metrics with earlier optimization reports.
- Do not count a missing response as a received classification.
- Retain the original CSV and JSON for traceability.
- Document any changes to the RTL, quantization, model, or validation configuration.