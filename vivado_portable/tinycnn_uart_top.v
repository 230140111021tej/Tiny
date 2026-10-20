`timescale 1ns/1ps

module tinycnn_uart_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire uart_rxd,
    output wire uart_txd,
    output reg [3:0] led,
    output reg [6:0] seg,
    output wire [3:0] an,
    output wire dp
);

    localparam WAIT_A5    = 3'd0;
    localparam WAIT_5A    = 3'd1;
    localparam RECEIVE    = 3'd2;
    localparam INFER      = 3'd3;
    localparam SEND_RESULT = 3'd4;
localparam SELECT_SCORE = 3'd5;
localparam RESULT_READY = 3'd6;

    reg [2:0] state;

    wire [7:0] rx_data;
    wire rx_valid;

    reg pixel_load;
    reg [9:0] pixel_addr;
    reg [7:0] pixel_data;
    reg cnn_start;

    wire cnn_busy;
    wire cnn_done;
    wire [319:0] scores_flat;

    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    wire tx_done;

    reg [9:0] pixel_count;
    integer i;
    integer best_class;
    reg signed [31:0] best_score;
    reg signed [31:0] candidate_score;

    uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_rx (
        .clk(clk),
        .rst(rst),
        .rx(uart_rxd),
        .data(rx_data),
        .valid(rx_valid)
    );

    uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .start(tx_start),
        .data(tx_data),
        .tx(uart_txd),
        .busy(tx_busy),
        .done(tx_done)
    );

    tinycnn_core u_cnn (
        .clk(clk),
        .rst(rst),
        .start(cnn_start),
        .pixel_load(pixel_load),
        .pixel_addr(pixel_addr),
        .pixel_data(pixel_data),
        .busy(cnn_busy),
        .done(cnn_done),
        .scores_flat(scores_flat)
    );

    always @(posedge clk) begin
        if (rst) begin
            state       <= WAIT_A5;
            pixel_count <= 0;
            pixel_load  <= 0;
            pixel_addr  <= 0;
            pixel_data  <= 0;
            cnn_start   <= 0;
            tx_start    <= 0;
            tx_data     <= 0;
            led         <= 0;
            i           <= 0;
            best_class  <= 0;
            best_score  <= 0;
            candidate_score <= 0;
        end else begin
            pixel_load <= 0;
            cnn_start  <= 0;
            tx_start   <= 0;

            case (state)
                WAIT_A5: begin
                    pixel_count <= 0;
                    if (rx_valid && rx_data == 8'hA5)
                        state <= WAIT_5A;
                end

                WAIT_5A: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h5A) begin
                            pixel_count <= 0;
                            state <= RECEIVE;
                        end else if (rx_data != 8'hA5) begin
                            state <= WAIT_A5;
                        end
                    end
                end

                RECEIVE: begin
                    if (rx_valid) begin
                        pixel_load <= 1;
                        pixel_addr <= pixel_count;
                        pixel_data <= rx_data;

                        if (pixel_count == 783) begin
                            pixel_count <= 0;
                            cnn_start <= 1;
                            state <= INFER;
                        end else begin
                            pixel_count <= pixel_count + 1'b1;
                        end
                    end
                end

                INFER: begin
                    if (cnn_done) begin
                        best_class <= 0;
                        best_score <= $signed(scores_flat[31:0]);
                        i <= 1;
                        state <= SELECT_SCORE;
                    end
                end

                SELECT_SCORE: begin
                    candidate_score = $signed(scores_flat[i*32 +: 32]);

                    // Strict greater-than preserves the lower index on ties.
                    if (candidate_score > best_score) begin
                        best_score <= candidate_score;
                        best_class <= i;
                    end

                    if (i == 9) begin
                        state <= RESULT_READY;
                    end else begin
                        i <= i + 1;
                    end
                end

                RESULT_READY: begin
                    tx_data <= best_class[7:0];
                    led <= best_class[3:0];
                    state <= SEND_RESULT;
                end

                SEND_RESULT: begin
                    if (!tx_busy && !tx_start) begin
                        tx_start <= 1;
                        state <= WAIT_A5;
                    end
                end

                default: state <= WAIT_A5;
            endcase
        end
    end


    // SEVEN_SEGMENT_DECODER
    // Active-low Basys 3 display; show the predicted class on the rightmost digit.
    assign an = 4'b1110;
    assign dp = 1'b1;

    always @* begin
        case (led)
            4'd0: seg = 7'b1000000;
            4'd1: seg = 7'b1111001;
            4'd2: seg = 7'b0100100;
            4'd3: seg = 7'b0110000;
            4'd4: seg = 7'b0011001;
            4'd5: seg = 7'b0010010;
            4'd6: seg = 7'b0000010;
            4'd7: seg = 7'b1111000;
            4'd8: seg = 7'b0000000;
            4'd9: seg = 7'b0010000;
            default: seg = 7'b1111111;
        endcase
    end
endmodule