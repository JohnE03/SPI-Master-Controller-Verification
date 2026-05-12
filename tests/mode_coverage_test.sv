`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV
 
class mode_coverage_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn t;
        bit [31:0] rd;
        $display("\n==================================================================");
        $display("[INFO] mode_coverage_test: STARTING");
        $display("==================================================================");
 
        for (int m = 0; m < 4; m++) begin
            t = new();
            if (!t.randomize() with {
                mode == m;           // Force the loop mode
                width == 2'b00;      // Pin width to 8-bit for isolation
                lsb_first == 1'b0;   // Pin MSB-first for isolation
                loopback == 1'b0; 
                clk_div inside {[2:8]}; // Keep it fast
            }) begin
                $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                ref_model.error_count++;
                return;
            end
 
            $display("\n------------------------------------------------------------------");
            $display("[INFO] Iteration %0d: Testing SPI Mode %0d", m, m);
            $display("[INFO] Generated Transaction: %s", t.sprint());
            $display("------------------------------------------------------------------");
 
            $display("[TRACE] Step 1: Synchronizing Slave BFM (Mode=%0d, Width=8b, MSB-first)", t.mode);
            tb_top.bfm_mode = t.mode;
            tb_top.bfm_width = t.width;
            tb_top.bfm_lsb_first = t.lsb_first;
            tb_top.bfm_pattern = 32'h0000_00A5;
 
            $display("[TRACE] Step 2: Configuring DUT Registers via APB");
            tb_top.u_apb_bfm.apb_write(8'h00, {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11}); // CTRL
            tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div}); // CLK_DIV
            tb_top.u_apb_bfm.apb_write(8'h18, 32'h0000_000F);      // INT_EN
 
            $display("[TRACE] Step 3: Registering expected values with the Scoreboard Predictor");
            ref_model.predict_single_byte(.tx_byte(t.tx_data[7:0]), .miso_pattern(tb_top.bfm_pattern[7:0]), .loopback(t.loopback));
            coverage.sample_config(.mode(t.mode), .lsb_first(t.lsb_first), .width(t.width));
 
            $display("[TRACE] Step 4: Pushing TX Data (0x%02h) and asserting Slave Select (SS_n[0])", t.tx_data[7:0]);
            tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);
 
            $display("[TRACE] Step 5: Polling STATUS.BUSY until hardware completes the transfer...");
            repeat (500) begin
                tb_top.u_apb_bfm.apb_read(8'h04, rd);
                if (rd[0] == 1'b0) break;
            end
            $display("[TRACE] Step 5 Complete: Transfer finished.");
 
            $display("[TRACE] Step 6: Popping RX FIFO and triggering Scoreboard Check");
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
            ref_model.check_rx(rd);
            $display("[TRACE] Step 7: Deasserting Slave Select");
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000); // Deassert SS
        end
        $display("\n==================================================================");
        $display("[INFO] mode_coverage_test: FINISHED");
        $display("==================================================================");
    endtask
endclass
`endif