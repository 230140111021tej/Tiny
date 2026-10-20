# Validation Methodology

## Objective
Evaluate the deployed TinyCNN FPGA implementation on the MNIST test dataset and compare received predictions with the labels.

## Interface
- Image: 28 × 28 pixels
- Pixels: 784 unsigned 8-bit values
- UART: 115200 baud, 8-N-1
- Packet prefix: `A5 5A`
- Response: one predicted class byte

## Procedure
1. Export MNIST test images to the project's validation format.
2. Program the recorded V7 bitstream onto the Basys 3.
3. Run the host-side UART batch validation script.
4. Record true label, predicted label, status, round-trip time, and communication errors.
5. Compare received FPGA predictions with integer and floating-point software references.
6. Preserve CSV/JSON results, scripts, quantization parameters, and implementation reports.

## Recorded result
The run attempted 10,000 images and received 9,999 predictions. Of the received responses, 9,465 were correct and 534 were incorrect. One attempt had no response.

- Accuracy among responses: 9,465 / 9,999 = 94.66%.
- Correct predictions / all attempts: 9,465 / 10,000 = 94.65%.

The software comparison reported 94.65% floating-point accuracy, 94.67% integer-reference accuracy, and 94.66% FPGA accuracy among received samples. FPGA and integer-reference outputs agreed on 9,998 of 9,999 received samples.

## Limitations
- UART round-trip time includes transfer and host-side overhead; it is not pure inference latency.
- Routed power is a medium-confidence estimate, not a board-level measurement.
- One response was missing in the recorded batch.
- Results apply to this model, dataset, bitstream, and test setup; they do not establish superiority over CPU/GPU.
