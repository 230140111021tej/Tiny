`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [7:0] data,
    output reg tx,
    output reg busy,
    output reg done
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    reg [15:0] count;
    reg [3:0] bit_index;
    reg [9:0] frame;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            count <= 0;
            bit_index <= 0;
            frame <= 10'h3FF;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                tx <= 1'b1;
                if (start) begin
                    frame <= {1'b1, data, 1'b0};
                    tx <= 1'b0;
                    busy <= 1'b1;
                    count <= CLKS_PER_BIT - 1;
                    bit_index <= 0;
                end
            end else if (count != 0) begin
                count <= count - 1'b1;
            end else begin
                count <= CLKS_PER_BIT - 1;
                bit_index <= bit_index + 1'b1;

                if (bit_index == 9) begin
                    busy <= 1'b0;
                    tx <= 1'b1;
                    done <= 1'b1;
                end else begin
                    tx <= frame[bit_index + 1'b1];
                end
            end
        end
    end
endmodule
