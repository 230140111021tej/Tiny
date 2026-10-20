`timescale 1ns/1ps
module uart_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;

    localparam [1:0] IDLE  = 2'd0,
                     START = 2'd1,
                     DATA  = 2'd2,
                     STOP  = 2'd3;

    reg rx_meta, rx_sync;
    reg [15:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift;
    reg [1:0] state;

    // Synchronize the asynchronous UART input.
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // Verify the start bit before sampling the eight data bits.
    always @(posedge clk) begin
        if (rst) begin
            count     <= 0;
            bit_index <= 0;
            shift     <= 0;
            state     <= IDLE;
            data      <= 0;
            valid     <= 0;
        end else begin
            valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (!rx_sync) begin
                        count <= HALF_BIT - 1;
                        state <= START;
                    end
                end

                START: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else if (!rx_sync) begin
                        count     <= CLKS_PER_BIT - 1;
                        bit_index <= 0;
                        state     <= DATA;
                    end else begin
                        // False start: return to idle.
                        state <= IDLE;
                    end
                end

                DATA: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else begin
                        shift[bit_index] <= rx_sync;

                        if (bit_index == 7) begin
                            count <= CLKS_PER_BIT - 1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            count <= CLKS_PER_BIT - 1;
                        end
                    end
                end

                STOP: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else begin
                        if (rx_sync) begin
                            data  <= shift;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
