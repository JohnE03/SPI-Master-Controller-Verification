`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

class delay_transfer_test;

    //  checker task to verify the exact idle SCLK gap
    // between two consecutive transfers according to DELAY and CLK_DIV
    static task automatic check_delay_gap(
        input int delay_cfg,
        input int clk_div,
        output bit gap_error
    );
        int edge_count;
        int gap_pclks;
        int expected_gap;
        bit sclk_prev;
        bit sclk_now;
        bit measuring_gap;

        edge_count    = 0;
        gap_pclks     = 0;
        measuring_gap = 0;
        gap_error     = 0;

       
      
   
    // one SCLK half-cycle = (CLK_DIV + 1) PCLK cycles
        expected_gap = delay_cfg * (clk_div + 1);
       
        @(posedge tb_top.PCLK);
        sclk_prev = tb_top.u_wrap.u_dut.u_core.SCLK;

        wait (tb_top.u_wrap.u_dut.u_core.busy == 1'b1);

        forever begin
            @(posedge tb_top.PCLK);
            sclk_now = tb_top.u_wrap.u_dut.u_core.SCLK;

            //  count idle PCLK cycles between transfers
            if (measuring_gap)
                gap_pclks++;

            if (sclk_now != sclk_prev) begin
                edge_count++;

                //  first 8-bit word completes after 16 SCLK edges
                if (edge_count == 16) begin
                    measuring_gap = 1;
                    gap_pclks = 0;
                end

                //  first edge of second transfer detected
                else if (edge_count == 17) begin
                    int fsm_overhead;
                    int total_expected_pclks;

                    // Add physical hardware overhead
                    if (delay_cfg == 0) fsm_overhead = 4;
                    else                fsm_overhead = 7;

                    total_expected_pclks = expected_gap + fsm_overhead;

                    if (gap_pclks !== total_expected_pclks) begin
                        $display("[SCOREBOARD_ERROR] DELAY measurement failed! Expected %0d PCLKs, observed %0d PCLKs", 
                                  total_expected_pclks, gap_pclks);
                        gap_error = 1;
                    end else begin
                        $display("[CHECKER] DELAY match: DELAY=%0d DIV=%0d gap=%0d PCLKs", 
                                  delay_cfg, clk_div, gap_pclks);
                    end
                    return;
                end
                sclk_prev = sclk_now;
            end
        end
    endtask


    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn t;
        bit [31:0] rd;
        bit gap_error;

        int delay_values[4] = '{0, 1, 128, 255};

        $display("\n==================================================================");
        $display("[INFO] delay_transfer_test: STARTING");
        $display("==================================================================");

        foreach (delay_values[i]) begin

            t = new();

            // allow delay values bigger than default sane range [0:31]
            t.c_delay_sane.constraint_mode(0);

            if (!t.randomize() with {
                delay_cfg == delay_values[i];
                clk_div   == 16'h0002;
                width     == 2'b00;
                loopback  == 1'b1;
            }) begin
                $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                gap_error = 1;
                return;
            end

            $display("\n------------------------------------------------------------------");
            $display("[INFO] Testing DELAY_CFG = %0d", t.delay_cfg);
            $display("------------------------------------------------------------------");

            tb_top.bfm_mode      = t.mode;
            tb_top.bfm_width     = t.width;
            tb_top.bfm_lsb_first = t.lsb_first;

            // Configure DUT
            tb_top.u_apb_bfm.apb_write(
                8'h00,
                {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11}
            );

            tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});

            // Program DELAY register
            tb_top.u_apb_bfm.apb_write(8'h20, {24'h0, t.delay_cfg});
            //coverage.sample_timing(t.clk_div[15:0], t.delay_cfg[7:0]); // added    
            coverage.sample_delay(t.delay_cfg[7:0]); // added
           gap_error = 0;

        fork
            check_delay_gap(t.delay_cfg, t.clk_div, gap_error);
        join_none

            // Predict two transfers
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

            // Queue two words so inter-transfer delay occurs
            tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00A5);
            tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_003C);

            // Assert SS
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);

            $display("[TRACE] Waiting for transfer completion");

            repeat (100000) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);

                if (rd[0] == 1'b0)
                    break;
            end

        //     #1;

            if (gap_error) begin
                ref_model.error_count++;
            end
            // Read first RX word
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
            ref_model.pop_and_check_rx(rd);

            // Read second RX word
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
            ref_model.pop_and_check_rx(rd);

            // Deassert SS
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);

            $display("[TRACE] DELAY=%0d transfer sequence completed successfully",
                     t.delay_cfg);
        end

        $display("\n==================================================================");
        $display("[INFO] delay_transfer_test: FINISHED");
        $display("==================================================================");
    endtask

endclass

`endif