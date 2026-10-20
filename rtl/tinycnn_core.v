`timescale 1ns/1ps

module tinycnn_core (
    input  wire clk,
    input  wire rst,
    input  wire start,
    output reg  busy,
    output reg  done,
    output reg  signed [31:0] scores [0:9]
);

    localparam IDLE = 3'd0,
               CONV = 3'd1,
               POOL = 3'd2,
               FC   = 3'd3,
               DONE = 3'd4;

    localparam integer MULT  = 54688;
    localparam integer SHIFT = 24;

    reg [2:0] state;

    reg [7:0] pixels [0:783];
    reg signed [7:0] conv_w [0:35];
    reg signed [31:0] conv_b [0:3];
    reg signed [7:0] fc_w [0:6759];
    reg signed [31:0] fc_b [0:9];

    reg [7:0] conv_map [0:2703];
    reg [7:0] pooled [0:675];

    integer ci;
    integer fi;
    integer neuron;
    integer ch;
    integer oy;
    integer ox;
    integer py;
    integer px;
    integer k;
    integer a;
    integer b;
    integer idx;
    integer feature;
    integer product_value;
    integer accumulator;
    integer max_value;
    reg signed [63:0] scaled;

    initial begin
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/test_image_u8.mem", pixels);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/conv1_weights_int8.mem", conv_w);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/conv1_bias_int32.mem", conv_b);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/fc1_weights_int8.mem", fc_w);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/fc1_bias_int32.mem", fc_b);
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            ci    <= 0;
            fi    <= 0;
            neuron <= 0;
            for (k = 0; k < 10; k = k + 1)
                scores[k] <= 0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        ci <= 0;
                        state <= CONV;
                    end
                end

                CONV: begin
                    ch = ci / 676;
                    oy = (ci % 676) / 26;
                    ox = ci % 26;

                    accumulator = conv_b[ch];

                    for (a = 0; a < 3; a = a + 1) begin
                        for (b = 0; b < 3; b = b + 1) begin
                            idx = (oy + a) * 28 + ox + b;
                            k = ch * 9 + a * 3 + b;
                            product_value =
                                $signed({1'b0, pixels[idx]}) *
                                $signed(conv_w[k]);
                            accumulator = accumulator + product_value;
                        end
                    end

                    if (accumulator < 0)
                        accumulator = 0;

                    scaled = accumulator;
                    scaled = scaled * MULT;
                    scaled = scaled + (1 << (SHIFT - 1));
                    scaled = scaled >>> SHIFT;

                    if (scaled > 255)
                        conv_map[ci] <= 8'd255;
                    else
                        conv_map[ci] <= scaled[7:0];

                    if (ci == 2703) begin
                        fi <= 0;
                        state <= POOL;
                    end else begin
                        ci <= ci + 1;
                    end
                end

                POOL: begin
                    ch = fi / 169;
                    py = (fi % 169) / 13;
                    px = fi % 13;

                    idx = ch * 676 + (2 * py) * 26 + (2 * px);

                    max_value = conv_map[idx];
                    if (conv_map[idx + 1] > max_value)
                        max_value = conv_map[idx + 1];
                    if (conv_map[idx + 26] > max_value)
                        max_value = conv_map[idx + 26];
                    if (conv_map[idx + 27] > max_value)
                        max_value = conv_map[idx + 27];

                    pooled[fi] <= max_value[7:0];

                    if (fi == 675) begin
                        neuron <= 0;
                        fi <= 0;
                        for (k = 0; k < 10; k = k + 1)
                            scores[k] <= fc_b[k];
                        state <= FC;
                    end else begin
                        fi <= fi + 1;
                    end
                end

                FC: begin
                    feature = neuron * 676 + fi;

                    product_value =
                        $signed({1'b0, pooled[fi]}) *
                        $signed(fc_w[feature]);

                    scores[neuron] <= scores[neuron] + product_value;

                    if (fi == 675) begin
                        fi <= 0;
                        if (neuron == 9) begin
                            state <= DONE;
                        end else begin
                            neuron <= neuron + 1;
                        end
                    end else begin
                        fi <= fi + 1;
                    end
                end

                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule


