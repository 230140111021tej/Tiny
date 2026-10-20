# TinyCNN FPGA Validation Guide

Run commands from the repository root (`tiny_cnn`) in PowerShell.

## Hardware and tools

- Board: Digilent Basys 3
- FPGA: XC7A35T-1CPG236
- Vivado: 2025.1
- Python: available as `python` on `PATH`
- UART: 115200 baud, 8-N-1

Use the COM port currently assigned to the board. COM4 was used for a recorded test, but is not universal.

## 1. Export MNIST validation images

Exporter: `scripts\export_mnist_validation.py`

Set `$dataDir` to the folder containing the MNIST IDX files. In the original workspace, the data directory is a sibling of this repository under `data\MNIST\raw`.

```powershell
$dataDir = Join-Path (Split-Path $PWD.Path -Parent) "data\MNIST\raw"
Test-Path (Join-Path $dataDir "t10k-images-idx3-ubyte")
Test-Path (Join-Path $dataDir "t10k-labels-idx1-ubyte")

python .\scripts\export_mnist_validation.py `
  --count 10000 `
  --data-dir $dataDir
```

Both `Test-Path` checks should return `True` before exporting. If the dataset is elsewhere, set `$dataDir` to that location. Compressed `.gz` IDX files are also supported.

Exported images are written under `validation\mnist10000`. Exporting does not retrain the model or modify the FPGA bitstream.

## 2. Run a short hardware test first

Ensure the intended bitstream is programmed and the Basys 3 is connected. Find the current serial port:

```powershell
[System.IO.Ports.SerialPort]::GetPortNames()
```

Replace `COM4` below if Windows reports a different port:

```powershell
.\scripts\run_uart_batch_test.ps1 `
  -Dataset mnist10 `
  -PortName COM4 `
  -BaudRate 115200
```

Run a large batch only after the short test completes successfully.

## 3. Full validation (optional)

```powershell
.\scripts\run_uart_batch_test.ps1 `
  -Dataset mnist10000 `
  -PortName COM4 `
  -BaudRate 115200
```

Use the actual COM port. A full hardware test can take a long time; rerunning it is unnecessary if the recorded results meet your needs. New runs write timestamped CSV and JSON files under `validation\results`.

## 4. Recorded full-test result

- CSV: `validation/results/mnist10000_results_20261020_122444.csv`
- Summary: `validation/results/mnist10000_summary_20261020_122444.json`
- Attempts: 10,000
- Responses received: 9,999
- Correct predictions: 9,465
- Misclassified received images: 534
- Missing responses: 1
- Accuracy among received responses: 94.66%
- Correct predictions divided by all attempts: 94.65%

Keep classification errors separate from missing UART responses. These are results from the recorded run, not a guarantee that a later run will be identical.

## 5. Software comparison

Recorded comparison:
- Floating-point reference: 94.65%
- Integer reference: 94.67%
- FPGA on received responses: 94.66%
- Integer-reference/FPGA agreement: 9,998 of 9,999 responses

The helper script used for the recorded comparison is not included in this repository, so the comparison is not reproducible from this repository alone. A reproduction requires the helper, model checkpoint, quantization settings, dataset, and input CSV.

## 6. Timing, resources, and power

Use the committed V7 routed reports:

- Timing: `reports/v7/routed_timing.rpt`
- Utilization: `reports/v7/routed_utilization.rpt`
- Power: `reports/v7/routed_power.rpt`

The power report is a medium-confidence Vivado estimate, not a direct physical measurement. UART round-trip time includes serial communication and host overhead; it must not be reported as pure FPGA inference latency.

The packaged bitstream is `release/tinycnn_uart_v7.bit`.

## 7. Safeguards

- Preserve the known-good V7 bitstream and RTL.
- Do not mix V7 routed metrics with earlier optimization reports.
- Do not count a missing response as a received classification.
- Retain original CSV and JSON files for traceability.
- Document changes to RTL, quantization, model weights, or validation configuration.
