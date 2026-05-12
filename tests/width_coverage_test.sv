`ifndef WIDTH_COVERAGE_TEST_SV
`define WIDTH_COVERAGE_TEST_SV
 
class width_coverage_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn t;
        bit [31:0] rd;
        $display("\n==================================================================");
        $display("[INFO] width_coverage_test: STARTING");
        $display("==================================================================");
 
        for (int w = 0; w < 3; w++) begin
            for (int lsb = 0; lsb < 2; lsb++) begin
                t = new();
                if (!t.randomize() with {
                    mode == 2'b00;       // Pin mode 0
                    width == w;          // Loop width (00, 01, 10)
                    lsb_first == lsb;    // Loop shift direction
                    loopback == 1'b1;    // Use loopback to test pure shifter routing
                    clk_div inside {[2:8]}; 
                }) begin
                    $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
                    ref_model.error_count++;
                    return;
                end
 
                $display("\n------------------------------------------------------------------");
                $display("[INFO] Width/LSB Test -> Width: %0d (0=8b, 1=16b, 2=32b) | LSB_First: %0b", w, lsb);
                $display("[INFO] Generated Transaction: %s", t.sprint());
                $display("------------------------------------------------------------------");
 
                $display("[TRACE] Step 1: Synchronizing Slave BFM (Mode 0, Loopback ON)");
                tb_top.bfm_mode = t.mode;
                tb_top.bfm_width = t.width;
                tb_top.bfm_lsb_first = t.lsb_first;
                $display("[TRACE] Step 2: Configuring DUT Registers via APB");
                tb_top.u_apb_bfm.apb_write(8'h00, {24'h0, t.width, t.loopback, t.lsb_first, t.mode, 2'b11});
                tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});
 
                $display("[TRACE] Step 3: Registering expected values with the Scoreboard Predictor");
                // NOTE: Because loopback is ON, expected RX is exactly the TX data.
                ref_model.predict_single_byte(.tx_byte(t.tx_data[7:0]), .miso_pattern(8'h00), .loopback(t.loopback));
                coverage.sample_config(.mode(t.mode), .lsb_first(t.lsb_first), .width(t.width));
 
                $display("[TRACE] Step 4: Pushing TX Data (0x%08h) and asserting Slave Select (SS_n[0])", t.tx_data);
                tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);
                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);
 
                $display("[TRACE] Step 5: Polling STATUS.BUSY until hardware completes the transfer...");
                repeat (1000) begin
                    tb_top.u_apb_bfm.apb_read(8'h04, rd);
                    if (rd[0] == 1'b0) break;
                end
                $display("[TRACE] Step 5 Complete: Transfer finished.");
 
                $display("[TRACE] Step 6: Popping RX FIFO and triggering Scoreboard Check");
                tb_top.u_apb_bfm.apb_read(8'h0C, rd);
                ref_model.check_rx(rd);
                $display("[TRACE] Step 7: Deasserting Slave Select");
                tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
            end
        end
        $display("\n==================================================================");
        $display("[INFO] width_coverage_test: FINISHED");
        $display("==================================================================");
    endtask
endclass
`endif