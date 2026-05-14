// =============================================================================
// error_injection_test.sv - Member 5: overflow, underflow, reserved (R13-R15,R23)
// =============================================================================
`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV

class error_injection_test extends base_test;
    function new(virtual apb_if apb_vif, virtual spi_if spi_vif);
        super.new(apb_vif, spi_vif);
        test_name = "error_injection_test";
    endfunction

    virtual task run_test_body();
        logic [31:0] rd, status;

        spi_bfm.mode      = 2'b00;
        spi_bfm.width     = 2'b00;
        spi_bfm.lsb_first = 1'b0;
        spi_bfm.miso_pattern = 32'h3C3C_3C3C;

        // Test 1: TX overflow (R13)
        apb_bfm.reg_write(8'h1C, 32'h001F);
        apb_bfm.reg_write(8'h18, 32'h001F);
        apb_bfm.configure_dut(.mode(2'b00), .width(2'b00), .clk_div(16'd2));
        for (int i = 0; i < 8; i++) apb_bfm.push_tx(32'hAA + i);
        apb_bfm.push_tx(32'hFF);  // 9th -> overflow
        apb_bfm.reg_read(8'h04, status);
        if (!status[5]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R13: TX_OVF not set after write to full TX FIFO");
        end
        apb_bfm.reg_read(8'h1C, rd);
        cov.sample_irq(rd[4:0], 5'h1F);
        if (!rd[2]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R13: INT_STAT[TX_OVF] not set");
        end
        apb_bfm.assert_ss();
        repeat(8) apb_bfm.wait_transfer_done();
        apb_bfm.deassert_ss();
        for (int i = 0; i < 8; i++) apb_bfm.pop_rx(rd);
        apb_bfm.reg_write(8'h1C, 32'h001F);

        // Test 2: RX read when empty -> 0, no OVF (R15)
        apb_bfm.reg_write(8'h00, 32'h0);
        apb_bfm.reg_write(8'h00, 32'h0000_0003);
        apb_bfm.pop_rx(rd);
        if (rd !== 32'h0) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R15: Empty RX read: exp=0 got=0x%08h", rd);
        end
        apb_bfm.reg_read(8'h04, status);
        if (status[6]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R15: RX_OVF set on empty read (must not be)");
        end

        // Test 3: TX write while EN=0 silently ignored
        apb_bfm.reg_write(8'h00, 32'h0);
        apb_bfm.push_tx(32'hAA);
        apb_bfm.reg_write(8'h00, 32'h0000_0003);
        apb_bfm.reg_read(8'h04, status);
        if (!status[2]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] TX write when EN=0 was NOT ignored (TX_EMPTY=0)");
        end

        // Test 4: RX overflow (R14)
        apb_bfm.configure_dut(.mode(2'b00), .width(2'b00), .clk_div(16'd2));
        apb_bfm.reg_write(8'h1C, 32'h001F);
        apb_bfm.assert_ss();
        for (int i = 0; i < 8; i++) apb_bfm.push_tx(32'hBB);
        repeat(8) apb_bfm.wait_transfer_done();
        apb_bfm.push_tx(32'hCC);
        apb_bfm.wait_transfer_done();
        apb_bfm.deassert_ss();
        apb_bfm.reg_read(8'h04, status);
        if (!status[6]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R14: RX_OVF not set after xfer to full RX FIFO");
        end
        apb_bfm.reg_read(8'h1C, rd);
        cov.sample_irq(rd[4:0], 5'h1F);
        if (!rd[3]) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R14: INT_STAT[RX_OVF] not set");
        end
        for (int i = 0; i < 8; i++) apb_bfm.pop_rx(rd);
        apb_bfm.reg_write(8'h1C, 32'h001F);

        // Test 5: Reserved offsets read as 0 (R23)
        apb_bfm.reg_write(8'h24, 32'hDEAD_BEEF);
        apb_bfm.reg_read(8'h24, rd);
        if (rd !== 32'h0) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R23: Reserved 0x24 = 0x%08h (exp 0)", rd);
        end
        apb_bfm.reg_write(8'h30, 32'hCAFE_BABE);
        apb_bfm.reg_read(8'h30, rd);
        if (rd !== 32'h0) begin
            sb.error_count++;
            $error("[SCOREBOARD_ERROR] R23: Reserved 0x30 = 0x%08h (exp 0)", rd);
        end

        apb_bfm.reg_write(8'h00, 32'h0);
    endtask
endclass

`endif
