`ifndef FLUSH_TEST_SV
`define FLUSH_TEST_SV

class flush_test;
    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        bit [31:0] rd;

        $display("[INFO] flush_test: starting");

        tb_top.bfm_mode    = 2'b00;
        tb_top.bfm_pattern = 8'h00; 

        // 1. Configure slow clock to ensure we can interrupt mid-transfer
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_00FF);
        
        // 2. Enable normal master mode
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0003);
        coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));

        // 3. Push data and start transfer
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00AA);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001); 

        // 4. Wait a few clock cycles to enter the SHIFT state
        repeat (20) @(posedge tb_top.PCLK);

        // 5. THE FLUSH: Drop EN to 0
        $display("[INFO] flush_test: Dropping CTRL.EN to 0 mid-transfer!");
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0002);
        ref_model.predict_flush();

        // 6. Verify STATUS is instantly cleared
        tb_top.u_apb_bfm.apb_read(8'h04, rd);
        
        // Expect: BUSY(0)=0, TX_EMPTY(2)=1, RX_EMPTY(4)=1
        if (rd[4] !== 1'b1 || rd[2] !== 1'b1 || rd[0] !== 1'b0) begin
            $display("[SCOREBOARD_ERROR] Flush failed. STATUS=0x%08h", rd);
            ref_model.error_count++;
        end

        // 7. Cleanup
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
        $display("[INFO] flush_test: finished.");
    endtask
endclass

`endif // FLUSH_TEST_SV