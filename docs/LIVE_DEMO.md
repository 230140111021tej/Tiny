# Live FPGA Demo

## Requirements
- Digilent Basys 3 FPGA board
- Windows PC with Vivado
- USB cable and serial COM port

## Program the FPGA
1. Connect the Basys 3 board.
2. Open Vivado Hardware Manager and connect to the target.
3. Program it with `release/tinycnn_uart_v7_sevenseg.bit`.
4. Confirm the COM port in Windows Device Manager.

## Run the live viewer
From the repository root, run:
.\scripts\live_uart_display.ps1

UART settings: 115200 baud, 8 data bits, no parity, 1 stop bit.
