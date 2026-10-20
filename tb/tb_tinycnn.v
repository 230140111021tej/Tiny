`timescale 1ns/1ps

module tb_tinycnn;
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    wire busy;
    wire done;
    wire signed [31:0] scores [0:9];

    reg [7:0] expected_pooled [0:675];
    reg signed [31:0] expected_scores [0:9];
    reg [7:0] expected_label_mem [0:0];

    integer i;
    integer errors;
    integer predicted;
    integer best_score;
    integer expected_label;

    tinycnn_core dut (
        .clk(clk), .rst(rst), .start(start),
        .busy(busy), .done(done), .scores(scores)
    );

    always #5 clk = ~clk;

    initial begin
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/expected_pooled_u8.mem", expected_pooled);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/expected_scores_int32.mem", expected_scores);
        $readmemh("D:/FPGA_EdgeAI/cnn_baseline/tiny_cnn/rom/expected_label.txt", expected_label_mem);

        expected_label = expected_label_mem[0];
        errors = 0;

        $display("TinyCNN RTL simulation starting");
        $display("Expected label: %0d", expected_label);

        #20;
        rst = 0;
        #10;
        start = 1;
        #10;
        start = 0;

        wait(done === 1'b1);
        #1;

        for (i = 0; i < 676; i = i + 1) begin
            if ((^dut.pooled[i]) === 1'bx) begin
                if (errors < 20)
                    $display("UNKNOWN pooled value at index %0d", i);
                errors = errors + 1;
            end else if (dut.pooled[i] !== expected_pooled[i]) begin
                if (errors < 20)
                    $display("POOL MISMATCH index=%0d RTL=%0d REF=%0d",
                        i, dut.pooled[i], expected_pooled[i]);
                errors = errors + 1;
            end
        end

        predicted = 0;
        best_score = scores[0];

        for (i = 0; i < 10; i = i + 1) begin
            if ((^scores[i]) === 1'bx) begin
                $display("UNKNOWN score at class %0d", i);
                errors = errors + 1;
            end else begin
                $display("Score[%0d]: RTL=%0d REF=%0d",
                         i, scores[i], expected_scores[i]);

                if (scores[i] !== expected_scores[i])
                    errors = errors + 1;

                if (scores[i] > best_score) begin
                    best_score = scores[i];
                    predicted = i;
                end
            end
        end

        if (predicted != expected_label) begin
            $display("LABEL MISMATCH: predicted=%0d expected=%0d",
                     predicted, expected_label);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("TINY_CNN_EXACT_REFERENCE_PASS");
            $display("Predicted digit = %0d", predicted);
        end else begin
            $display("TINY_CNN_REFERENCE_FAIL: %0d errors", errors);
            $fatal(1, "TinyCNN reference verification failed");
        end

        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "SIMULATION_TIMEOUT");
    end
endmodule
