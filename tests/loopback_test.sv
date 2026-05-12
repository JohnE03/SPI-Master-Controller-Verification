`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV

class loopback_test;
    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);
        bit [31:0] rd;

        $display("[INFO] loopback_test: starting");

        // 1. Force SPI slave to transmit garbage (0xFF)
        tb_top.bfm_mode    = 2'b00; 
        tb_top.bfm_pattern = 8'hFF; 

        // 2. Configure APB_CTRL (EN=1, MSTR=1, LOOPBACK=1) -> 0x23
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0023);
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0004);

        // 3. Update coverage & predictor
        coverage.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));
        ref_model.predict_single_byte(.tx_byte(8'h42),
                                      .miso_pattern(tb_top.bfm_pattern),
                                      .loopback(1'b1));

        // 4. Push test data (0x42) and assert SS
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_0042);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001); 

        // 5. Wait for transfer to finish
        repeat (500) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0) break; 
        end

        // 6. Read RX_DATA and check against the scoreboard
        tb_top.u_apb_bfm.apb_read(8'h0C, rd);
        ref_model.check_rx(rd); 

        // 7. Cleanup
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);
        $display("[INFO] loopback_test: finished.");
    endtask
endclass

`endif // LOOPBACK_TEST_SV