
`timescale 1ns/1ps

module tinycnn_core (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire pixel_load,
    input  wire [9:0] pixel_addr,
    input  wire [7:0] pixel_data,
    output reg  busy,
    output reg  done,
    output wire [319:0] scores_flat
);

    localparam IDLE         = 4'd0,
               CONV         = 4'd1,
               POOL         = 4'd2,
               FC           = 4'd3,
               DONE         = 4'd4,
               REQUANT_MUL   = 4'd10,
               REQUANT_SCALE = 4'd11,
               REQUANT_WRITE = 4'd12,
               CONV_PRODUCT = 4'd6,
               CONV_ACCUM   = 4'd7,
               FC_PRODUCT   = 4'd8,
               FC_ACCUM     = 4'd9;

    localparam integer MULT  = 54688;
    localparam integer SHIFT = 24;

    reg [3:0] state;

    reg [7:0] pixels [0:783];
    reg signed [7:0] conv_w [0:35];
    reg signed [31:0] conv_b [0:3];
    reg signed [7:0] fc_w [0:6759];
    reg signed [31:0] fc_b [0:9];

    reg [7:0] conv_map [0:2703];
    reg [7:0] pooled [0:675];
    reg signed [31:0] scores [0:9];

    genvar score_g;
    generate
        for (score_g = 0; score_g < 10; score_g = score_g + 1) begin : SCORE_PACK
            assign scores_flat[score_g*32 +: 32] = scores[score_g];
        end
    endgenerate

    // Sequential convolution: one kernel tap per clock.
    integer ci;
    reg [1:0] out_ch;
    reg [4:0] out_row;
    reg [4:0] out_col;
    reg [3:0] tap;
    reg [1:0] tap_row;
    reg [1:0] tap_col;

    integer conv_ch;
    integer conv_oy;
    integer conv_ox;
    integer conv_idx;
    integer conv_weight_idx;
    integer conv_product;
    integer conv_sum;

    reg signed [31:0] conv_accum;
    reg signed [8:0]  conv_pixel_reg;
    reg signed [7:0]  conv_weight_reg;
    reg signed [16:0] conv_product_reg;
    reg signed [31:0] conv_final_sum;
    reg signed [63:0] scaled;
    reg signed [63:0] requant_product;
    reg signed [63:0] requant_scaled;
    reg requant_negative;

    integer fi;
    integer neuron;
    integer ch;
    integer py;
    integer px;
    integer idx;
    integer k;
    integer feature;
    integer product_value;
    reg [7:0] fc_activation_reg;
    reg signed [7:0] fc_weight_reg;
    reg signed [15:0] fc_product_reg;
    reg [31:0] fc_feature_reg;
    reg [3:0] fc_neuron_reg;
    integer max_value;

    // Pooling: one memory read per cycle, then a separate max cycle.
    reg [2:0] pool_phase;
    reg [1:0] pool_ch;
    reg [3:0] pool_row;
    reg [3:0] pool_col;
    reg [7:0] pool_rd_data;
    reg [7:0] pool_val0;
    reg [7:0] pool_val1;
    reg [7:0] pool_val2;
    wire [11:0] pool_base_addr;
    reg [11:0] pool_read_addr;

    assign pool_base_addr =
        pool_ch * 12'd676 + pool_row * 12'd52 + pool_col * 12'd2;

    always @* begin
        case (pool_phase)
            3'd0: pool_read_addr = pool_base_addr;
            3'd1: pool_read_addr = pool_base_addr + 12'd1;
            3'd2: pool_read_addr = pool_base_addr + 12'd26;
            3'd3: pool_read_addr = pool_base_addr + 12'd27;
            default: pool_read_addr = pool_base_addr;
        endcase
    end

    initial begin
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/conv1_weights_int8.mem", conv_w);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/conv1_bias_int32.mem", conv_b);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/fc1_weights_int8.mem", fc_w);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/fc1_bias_int32.mem", fc_b);
    end

    always @(posedge clk) begin
        if (pixel_load)
            pixels[pixel_addr] <= pixel_data;

        if (rst) begin
            out_ch  <= 0;
            out_row <= 0;
            out_col <= 0;
            state      <= IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            ci         <= 0;
            tap        <= 0;
            tap_row    <= 0;
            tap_col    <= 0;
            conv_accum <= 0;
            fi         <= 0;
            neuron     <= 0;
            pool_phase <= 0;
            pool_ch    <= 0;
            pool_row   <= 0;
            pool_col   <= 0;
            pool_rd_data <= 0;
            pool_val0  <= 0;
            pool_val1  <= 0;
            pool_val2  <= 0;

            for (k = 0; k < 10; k = k + 1)
                scores[k] <= 0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        out_ch  <= 0;
                        out_row <= 0;
                        out_col <= 0;
                        busy       <= 1'b1;
                        ci         <= 0;
                        tap        <= 0;
                        tap_row    <= 0;
                        tap_col    <= 0;
                        conv_accum <= 0;
                        pool_phase <= 0;
                        pool_ch    <= 0;
                        pool_row   <= 0;
                        pool_col   <= 0;
                        state      <= CONV;
                    end
                end

                CONV: begin
                    // Stage 1: capture pixel and signed weight.
                    conv_ch = out_ch;
                    conv_oy = out_row;
                    conv_ox = out_col;

                    conv_idx = (conv_oy + tap_row) * 28
                             + conv_ox + tap_col;
                    conv_weight_idx = conv_ch * 9 + tap;

                    conv_pixel_reg <= {1'b0, pixels[conv_idx]};
                    conv_weight_reg <= conv_w[conv_weight_idx];
                    state <= CONV_PRODUCT;
                end

                CONV_PRODUCT: begin
                    // Stage 2: register signed multiplication.
                    conv_product_reg <= $signed(conv_pixel_reg) *
                                        $signed(conv_weight_reg);
                    state <= CONV_ACCUM;
                end

                CONV_ACCUM: begin
                    // Stage 3: accumulate product with bias or prior sum.
                    if (tap == 0)
                        conv_sum = conv_b[out_ch] + conv_product_reg;
                    else
                        conv_sum = conv_accum + conv_product_reg;

                    if (tap == 8) begin
                        conv_final_sum <= conv_sum;
                        conv_accum <= 0;
                        tap <= 0;
                        tap_row <= 0;
                        tap_col <= 0;
                        state <= REQUANT_MUL;
                    end else begin
                        conv_accum <= conv_sum;
                        tap <= tap + 1'b1;

                        if (tap_col == 2) begin
                            tap_col <= 0;
                            tap_row <= tap_row + 1'b1;
                        end else begin
                            tap_col <= tap_col + 1'b1;
                        end

                        state <= CONV;
                    end
                end

                REQUANT_MUL: begin
                    // Stage 1: register the multiplication result.
                    requant_negative <= (conv_final_sum < 0);
                    if (conv_final_sum < 0)
                        requant_product <= 64'sd0;
                    else
                        requant_product <=
                            $signed({32'd0, conv_final_sum}) * MULT;
                    state <= REQUANT_SCALE;
                end

                REQUANT_SCALE: begin
                    // Stage 2: register rounded and shifted result.
                    requant_scaled <=
                        (requant_product +
                         (64'sd1 <<< (SHIFT - 1))) >>> SHIFT;
                    state <= REQUANT_WRITE;
                end

                REQUANT_WRITE: begin
                    // Stage 3: clamp and write the current output.
                    if (requant_negative)
                        conv_map[ci] <= 8'd0;
                    else if (requant_scaled > 64'sd255)
                        conv_map[ci] <= 8'd255;
                    else if (requant_scaled < 0)
                        conv_map[ci] <= 8'd0;
                    else
                        conv_map[ci] <= requant_scaled[7:0];

                    if (ci == 2703) begin
                        fi <= 0;
                        pool_phase <= 0;
                        pool_ch <= 0;
                        pool_row <= 0;
                        pool_col <= 0;
                        state <= POOL;
                    end else begin
                        ci <= ci + 1;

                        if (out_col == 25) begin
                            out_col <= 0;
                            if (out_row == 25) begin
                                out_row <= 0;
                                out_ch <= out_ch + 1'b1;
                            end else begin
                                out_row <= out_row + 1'b1;
                            end
                        end else begin
                            out_col <= out_col + 1'b1;
                        end

                        state <= CONV;
                    end
                end
                POOL: begin
                    // Synchronous read: the sampled data is consumed
                    // on the following phase.
                    if (pool_phase != 3'd4)
                        pool_rd_data <= conv_map[pool_read_addr];

                    case (pool_phase)
                        3'd0: begin
                            pool_phase <= 3'd1;
                        end

                        3'd1: begin
                            pool_val0 <= pool_rd_data;
                            pool_phase <= 3'd2;
                        end

                        3'd2: begin
                            pool_val1 <= pool_rd_data;
                            pool_phase <= 3'd3;
                        end

                        3'd3: begin
                            pool_val2 <= pool_rd_data;
                            pool_phase <= 3'd4;
                        end

                        3'd4: begin
                            max_value = pool_val0;

                            if (pool_val1 > max_value)
                                max_value = pool_val1;
                            if (pool_val2 > max_value)
                                max_value = pool_val2;
                            if (pool_rd_data > max_value)
                                max_value = pool_rd_data;

                            pooled[fi] <= max_value[7:0];

                            if (fi == 675) begin
                                neuron <= 0;
                                fi <= 0;
                                pool_phase <= 0;

                                for (k = 0; k < 10; k = k + 1)
                                    scores[k] <= fc_b[k];

                                state <= FC;
                            end else begin
                                fi <= fi + 1;
                                pool_phase <= 0;

                                if (pool_col == 12) begin
                                    pool_col <= 0;
                                    if (pool_row == 12) begin
                                        pool_row <= 0;
                                        pool_ch <= pool_ch + 1'b1;
                                    end else begin
                                        pool_row <= pool_row + 1'b1;
                                    end
                                end else begin
                                    pool_col <= pool_col + 1'b1;
                                end
                            end
                        end

                        default: pool_phase <= 0;
                    endcase
                end
                FC: begin
                    feature = neuron * 676 + fi;
                    fc_activation_reg <= pooled[fi];
                    fc_weight_reg <= fc_w[feature];
                    fc_feature_reg <= fi;
                    fc_neuron_reg <= neuron;
                    state <= FC_PRODUCT;
                end

                FC_PRODUCT: begin
                    fc_product_reg <=
                        $signed({1'b0, fc_activation_reg}) *
                        $signed(fc_weight_reg);
                    state <= FC_ACCUM;
                end

                FC_ACCUM: begin
                    scores[fc_neuron_reg] <=
                        scores[fc_neuron_reg] + fc_product_reg;

                    if (fc_feature_reg == 675) begin
                        fi <= 0;
                        if (fc_neuron_reg == 9)
                            state <= DONE;
                        else begin
                            neuron <= fc_neuron_reg + 1;
                            state <= FC;
                        end
                    end else begin
                        fi <= fc_feature_reg + 1;
                        state <= FC;
                    end
                end
                DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule


