

`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV

class clk_div_corner_test;

    
// After transfer starts with old_div, mid-transfer writes must not change SCLK timing
static task automatic check_clk_div_hold(
    input int old_div,
    input int new_div,
    output bit div_hold_error
);
    int edge_count;
    int gap_count;
    int expected_gap;
    bit sclk_prev;
    bit sclk_now;
    bit write_done;

    edge_count     = 0;
    gap_count      = 0;
    div_hold_error = 0;
    write_done     = 0;

    expected_gap = old_div + 1;

    @(posedge tb_top.PCLK);
    sclk_prev = tb_top.u_wrap.u_dut.u_core.SCLK;

    wait (tb_top.u_wrap.u_dut.u_core.busy == 1'b1);

    forever begin
        @(posedge tb_top.PCLK);
        sclk_now = tb_top.u_wrap.u_dut.u_core.SCLK;

        gap_count++;

        if (sclk_now != sclk_prev) begin
            edge_count++;

            // after a few SCLK edges, change CLK_DIV while transfer is active
            if ((edge_count == 4) && !write_done) begin
                tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, new_div[15:0]});
                write_done = 1;
                $display("[TRACE] R25: Changed CLK_DIV mid-transfer from %0d to %0d",
                         old_div, new_div);
            end

            //  after the write, SCLK half-period must still match old_div
            if (write_done && (gap_count !== expected_gap)) begin
                $display("[SCOREBOARD_ERROR] R25 CLK_DIV hold failed: expected_gap=%0d observed_gap=%0d old_div=%0d new_div=%0d",
                         expected_gap, gap_count, old_div, new_div);
                div_hold_error = 1;
                return;
            end

            gap_count = 0;
            sclk_prev = sclk_now;
        end

        if (tb_top.u_wrap.u_dut.u_core.busy == 1'b0)
            return;
    end
endtask





    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn t;
        bit [31:0] rd;
        int corners[6] = '{0, 1, 2, 3, 255, 1024}; // corner cases and 65535 will be tested seperately due to long transfer time and exceeds the timeout of the testbench
        
        $display("\n==================================================================");
        $display("[INFO] clk_div_corner_test: STARTING");
        $display("==================================================================");

        foreach(corners[i]) begin
            t = new();
           t.c_clk_div_sane.constraint_mode(0); // Disable the default clk_div constraint to allow corner values bigger than 2048
            if (!t.randomize() with {
                clk_div == corners[i]; // Pin the corner case
                width == 2'b00;        // 8-bit to save time on the 65535 case
                mode == 2'b00;
                loopback == 1'b1;
            }) begin
                $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                ref_model.error_count++;
                return;
            end

            $display("\n------------------------------------------------------------------");
            $display("[INFO] Timing Corner Test: CLK_DIV = %0d", t.clk_div);
            $display("------------------------------------------------------------------");

            tb_top.bfm_mode = t.mode;
            tb_top.bfm_width = t.width;
            tb_top.bfm_lsb_first = t.lsb_first;
            
            $display("[TRACE] Step 1: Configuring DUT (DIV=%0d)", t.clk_div);
            tb_top.u_apb_bfm.apb_write(8'h00, {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11});
            tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});
            coverage.sample_clk_div(t.clk_div[15:0]);


            $display("[TRACE] Step 2: Requesting Scoreboard Timing Prediction");
            ref_model.predict_single_byte(.tx_byte(t.tx_data[7:0]), .miso_pattern(8'h00), .loopback(t.loopback));
            ref_model.predict_transfer_time(t.width, t.clk_div); // Trigger the new math formula
            
            $display("[TRACE] Step 3: Pushing TX Data and triggering transfer");
            tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

            $display("[TRACE] Step 4: Waiting for transfer completion");

            repeat (2_000_000) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);
                if (rd[0] == 1'b0) break;
            end

            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
            ref_model.pop_and_check_rx(rd);
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
            $display("[TRACE] Step 5: Transfer finished and checked successfully.");
        end

        for (int r = 0; r < 5; r++) begin
         t = new();

    // Keep random values practical for simulation runtime
    if (!t.randomize() with {
        clk_div inside {[4:128]};
        width    == 2'b00;
        mode     == 2'b00;
        loopback == 1'b1;
    }) begin
        $display("[SCOREBOARD_ERROR] random CLK_DIV randomization failed");
        ref_model.error_count++;
        return;
    end

        $display("\n------------------------------------------------------------------");
        $display("[INFO] Random CLK_DIV Timing Test: CLK_DIV = %0d", t.clk_div);
        $display("------------------------------------------------------------------");

        tb_top.bfm_mode      = t.mode;
        tb_top.bfm_width     = t.width;
        tb_top.bfm_lsb_first = t.lsb_first;

        // Configure DUT
        tb_top.u_apb_bfm.apb_write(8'h00, {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11});
        tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});
        coverage.sample_clk_div(t.clk_div[15:0]);

        // Predict expected RX and timing
        ref_model.predict_single_byte(
            .tx_byte(t.tx_data[7:0]),
            .miso_pattern(8'h00),
            .loopback(t.loopback)
        );

        ref_model.predict_transfer_time(t.width, t.clk_div);

        // Start transfer
        tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

        $display("[TRACE] Waiting for random CLK_DIV transfer completion");

        // Wait until BUSY becomes 0
        repeat (50_000) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0)
                break;
        end

        // Drain RX FIFO so it does not become full in the next iteration
        tb_top.u_apb_bfm.apb_read(8'h0C, rd);
        ref_model.pop_and_check_rx(rd);

        // Deassert slave select
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);

        $display("[TRACE] Random CLK_DIV transfer finished and checked.");

        end


        // ================================================================
        // MAX DIVIDER CONFIGURATION TEST (DIV = 65535)
        // Configuration/readback only to avoid extremely long runtime
        // ================================================================

        $display("\n------------------------------------------------------------------");
        $display("[INFO] Max Divider Configuration Test: CLK_DIV = 65535");
        $display("------------------------------------------------------------------");

        // Program DUT
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_FFFF);
        coverage.sample_clk_div(16'hFFFF); 
        // Read back CLK_DIV register
        tb_top.u_apb_bfm.apb_read(8'h10, rd);

        // Scoreboard check
        ref_model.check_reg("CLK_DIV_MAX", 32'h0000_FFFF, rd);

        $display("[TRACE] DIV=65535 configuration/readback completed.");  


// config hold test
// DIV, MODE, WIDTH, and LSB_FIRST must be sampled at transfer start

begin
    $display("\n------------------------------------------------------------------");
    $display("[INFO] R25 combined config hold test");
    $display("------------------------------------------------------------------");

    // Old sampled config:
    // WIDTH=8-bit, LOOPBACK=1, LSB_FIRST=0, MODE=0, EN=1, MSTR=1
    tb_top.u_apb_bfm.apb_write(8'h00,
        {24'h0, 2'b00, 1'b1, 1'b0, 2'b00, 2'b11});

    // Old sampled DIV = 2
    tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0002);

    ref_model.predict_single_byte(
        .tx_byte(8'hA5),
        .miso_pattern(8'h00),
        .loopback(1'b1)
    );

    // Start transfer
    tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00A5);
    tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

    // Wait until BUSY=1
    do begin
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
    end while (rd[0] == 1'b0);

    // Change all sampled config fields mid-transfer:
    // New CTRL: WIDTH=32-bit, LOOPBACK=1, LSB_FIRST=1, MODE=3, EN=1, MSTR=1
    tb_top.u_apb_bfm.apb_write(8'h00,
        {24'h0, 2'b10, 1'b1, 1'b1, 2'b11, 2'b11});

    // New DIV = 0
    tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0000);

    $display("[TRACE] R25: Changed DIV, MODE, WIDTH, LSB_FIRST mid-transfer");

    // Wait for current transfer completion
    repeat (10000) begin
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        if (rd[0] == 1'b0)
            break;
    end

    // If current transfer was corrupted by new config, RX check should catch it
    tb_top.u_apb_bfm.apb_read(8'h0C, rd);
    ref_model.pop_and_check_rx(rd);

    tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);

    $display("[TRACE] R25 combined config hold test completed");
end

        
        $display("\n==================================================================");
        $display("[INFO] clk_div_corner_test: FINISHED");
        $display("==================================================================");
    endtask
endclass
`endif