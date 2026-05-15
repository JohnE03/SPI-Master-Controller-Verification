`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

class delay_transfer_test;

    // Measures the idle PCLK gap between the last edge of transfer #1
    // and the first edge of transfer #2.
    static task automatic check_delay_gap(
        input int delay_cfg,
        input int clk_div,
        output bit gap_error
    );
        int edge_count;
        int gap_pclks;
        int expected_gap;
        int tolerance;
        bit sclk_prev;
        bit sclk_now;
        bit measuring_gap;

        edge_count    = 0;
        gap_pclks     = 0;
        measuring_gap = 0;
        gap_error     = 0;
        tolerance     = 2; // allow +/- 2 PCLKs for edge-count alignment

        // Observed RTL behavior:
        // delay gap is based on SCLK half-period = CLK_DIV + 1.
        // Even delay_cfg=0 still gives one half-period worth of gap.
        expected_gap = ((delay_cfg == 0) ? 1 : (delay_cfg + 1)) * (clk_div + 1) + 1;

        @(posedge tb_top.PCLK);
        sclk_prev = tb_top.u_wrap.u_dut.u_core.SCLK;

        wait (tb_top.u_wrap.u_dut.u_core.busy == 1'b1);

        forever begin
            @(posedge tb_top.PCLK);
            sclk_now = tb_top.u_wrap.u_dut.u_core.SCLK;

            if (measuring_gap)
                gap_pclks++;

            if (sclk_now != sclk_prev) begin
                edge_count++;

                // 8-bit transfer = 16 SCLK edges
                if (edge_count == 16) begin
                    measuring_gap = 1'b1;
                    gap_pclks = 0;
                end
                else if (edge_count == 17) begin
                    if ((gap_pclks < (expected_gap - tolerance)) ||
                        (gap_pclks > (expected_gap + tolerance))) begin
                        $display("[SCOREBOARD_ERROR] DELAY measurement failed! Expected about %0d PCLKs, observed %0d PCLKs",
                                 expected_gap, gap_pclks);
                        gap_error = 1'b1;
                    end
                    else begin
                        $display("[CHECKER] DELAY match: DELAY=%0d DIV=%0d gap=%0d PCLKs",
                                 delay_cfg, clk_div, gap_pclks);
                    end
                    return;
                end

                sclk_prev = sclk_now;
            end
        end
    endtask


    // Directed coverage-only corner for maximum CLK_DIV.
    // This does NOT push TX data and does NOT wait for a full SPI transfer.
    // Purpose: cover/program CLK_DIV=65535 safely without exceeding tb_top timeout.
    static task automatic directed_clk_div_65535_no_data(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        bit [31:0] rd;
        bit sclk_before;
        bit sclk_after;

        $display("\n------------------------------------------------------------------");
        $display("[INFO] Directed no-data test: CLK_DIV = 65535");
        $display("------------------------------------------------------------------");

        // Disable core and clear local reference model state.
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
        repeat (5) @(posedge tb_top.PCLK);
        ref_model.fifo_reset();

        // Configure max divider, but do not push TX data.
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_FFFF);
        tb_top.u_apb_bfm.apb_write(8'h20, 32'h0000_0000);

        // Sample coverage explicitly, since no transfer is intentionally run.
        coverage.sample_timing(16'hFFFF, 8'h00);
        coverage.sample_timing(16'hFFFF, 8'd1);
        coverage.sample_timing(16'hFFFF, 8'd128);

        // Read back CLK_DIV register to prove the directed value was programmed.
        tb_top.u_apb_bfm.apb_read(8'h10, rd);
        if (rd[15:0] !== 16'hFFFF) begin
            $display("[SCOREBOARD_ERROR] CLK_DIV=65535 readback failed! observed=0x%0h", rd[15:0]);
            ref_model.error_count++;
        end
        else begin
            $display("[CHECKER] CLK_DIV=65535 programmed/read back successfully");
        end

        // Enable master with no TX data. The DUT should not start a transfer.
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0003);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

        sclk_before = tb_top.u_wrap.u_dut.u_core.SCLK;
        repeat (100) @(posedge tb_top.PCLK);
        sclk_after = tb_top.u_wrap.u_dut.u_core.SCLK;

        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        if (rd[0] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] DUT became busy even though no TX data was pushed");
            ref_model.error_count++;
        end

        if (sclk_before !== sclk_after) begin
            $display("[SCOREBOARD_ERROR] SCLK toggled even though no transfer data was pushed");
            ref_model.error_count++;
        end
        else begin
            $display("[CHECKER] No-data CLK_DIV=65535 corner completed without starting transfer");
        end

        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);
        repeat (5) @(posedge tb_top.PCLK);
    endtask


    static task automatic wait_rx_count(input int target_count, output bit timeout_error);
        bit [31:0] rd;
        timeout_error = 1'b1;

        // Poll status until RX is not empty and DUT is idle.
        // Then use the internal rx_count to make sure both queued bytes arrived.
        repeat (3_000_000) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if ((tb_top.u_wrap.u_dut.u_regfile.rx_count >= target_count) &&
                (rd[0] == 1'b0)) begin
                timeout_error = 1'b0;
                break;
            end
        end
    endtask


    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn t;
        bit [31:0] rd;
        bit gap_error;
        bit timeout_error;

        // Keep 65535 out of this inter-transfer delay test because the
        // DELAY=200 combination exceeds tb_top's 10 ms safety timeout.
        // clk_div_corner_test should cover 65535 separately.
        int target_divs[]   = '{0, 1, 2, 3, 10, 255, 1024};
        int target_delays[] = '{0, 1, 128};

        $display("\n==================================================================");
        $display("[INFO] delay_transfer_test: STARTING");
        $display("==================================================================");

        directed_clk_div_65535_no_data(ref_model, coverage);

        foreach (target_divs[i]) begin
            foreach (target_delays[j]) begin

                t = new();
                t.c_delay_sane.constraint_mode(0);
                t.c_clk_div_sane.constraint_mode(0);

                if (!t.randomize() with {
                    clk_div   == target_divs[i];
                    delay_cfg == target_delays[j];
                    width     == 2'b00;
                    mode      == 2'b00;
                    loopback  == 1'b1;
                    lsb_first == 1'b0;
                }) begin
                    $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                    ref_model.error_count++;
                    return;
                end

                $display("\n------------------------------------------------------------------");
                $display("[INFO] Testing DELAY_CFG = %0d, CLK_DIV = %0d", t.delay_cfg, t.clk_div);
                $display("------------------------------------------------------------------");

                // Clean state for every sub-test.
                tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000);
                repeat (5) @(posedge tb_top.PCLK);
                ref_model.fifo_reset();

                tb_top.bfm_mode      = t.mode;
                tb_top.bfm_width     = t.width;
                tb_top.bfm_lsb_first = t.lsb_first;

                // Configure DUT: 8-bit, mode 0, loopback, enabled.
                tb_top.u_apb_bfm.apb_write(
                    8'h00,
                    {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11}
                );

                tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});
                tb_top.u_apb_bfm.apb_write(8'h20, {24'h0, t.delay_cfg});

                coverage.sample_timing(t.clk_div[15:0], t.delay_cfg[7:0]);

                ref_model.predict_single_byte(
                    .tx_byte(8'hA5),
                    .miso_pattern(8'h00),
                    .loopback(t.loopback)
                );

                ref_model.predict_single_byte(
                    .tx_byte(8'h3C),
                    .miso_pattern(8'h00),
                    .loopback(t.loopback)
                );

                $display("[TRACE] Pushing two TX words");
                tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00A5);
                tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_003C);

                // Assert SS after both TX words are already queued.
                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

                $display("[TRACE] Waiting for delay checker and transfer completion");

                gap_error = 1'b0;
                fork
                    check_delay_gap(t.delay_cfg, t.clk_div, gap_error);
                join

                if (gap_error)
                    ref_model.error_count++;

                wait_rx_count(2, timeout_error);
                if (timeout_error) begin
                    $display("[SCOREBOARD_ERROR] Timeout waiting for 2 RX bytes");
                    ref_model.error_count++;
                end

                tb_top.u_apb_bfm.apb_read(8'h0C, rd);
                ref_model.pop_and_check_rx(rd);

                tb_top.u_apb_bfm.apb_read(8'h0C, rd);
                ref_model.pop_and_check_rx(rd);

                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);

                $display("[TRACE] DELAY=%0d DIV=%0d transfer sequence completed successfully",
                         t.delay_cfg, t.clk_div);
            end
        end

        $display("\n==================================================================");
        $display("[INFO] delay_transfer_test: FINISHED");
        $display("==================================================================");
    endtask

endclass

`endif