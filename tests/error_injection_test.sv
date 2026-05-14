// =============================================================================
// error_injection_test.sv - Member 5: overflow, underflow, reserved (R13-R15,R23)
// =============================================================================
`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV

class error_injection_test;

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [31:0] rd, status;

        $display("\n==================================================================");
        $display("[INFO] error_injection_test: STARTING");
        $display("==================================================================");

        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_width     = 2'b00;
        tb_top.bfm_lsb_first = 1'b0;
        tb_top.bfm_pattern   = 32'h3C3C_3C3C;
        
        ref_model.fifo_reset();

        // Test 1: TX overflow (R13)
        $display("[TRACE] Test 1: TX overflow (R13)");
        tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_001F);
        tb_top.u_apb_bfm.apb_write(8'h18, 32'h0000_001F);
        
        // Configure DUT (Mode 0, 8-bit, Master, Enable)
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0003); 
        tb_top.u_apb_bfm.apb_write(8'h10, 32'h0000_0002);
        
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00AA + i);
        end
        
        // 9th -> overflow
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00FF);
        ref_model.push_tx(8'hFF); // Predict TX overflow in the scoreboard

        tb_top.u_apb_bfm.apb_read(8'h04, status);
        if (!status[5]) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R13: TX_OVF not set after write to full TX FIFO");
        end
        
        tb_top.u_apb_bfm.apb_read(8'h1C, rd);
        coverage.sample_interrupts(rd[4:0], 5'h1F);
        if (!rd[2]) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R13: INT_STAT[TX_OVF] not set");
        end

        // Drain TX FIFO
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001); // Assert SS
        repeat (5000) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0 && rd[2] == 1'b1) break; // Wait until BUSY=0 and TX_EMPTY=1
        end
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000); // Deassert SS
        
        // Empty the RX side
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
        end
        tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_001F); // Clear interrupts

        // Test 2: RX read when empty -> 0, no OVF (R15)
        $display("[TRACE] Test 2: RX read when empty (R15)");
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0);
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0003);
        
        tb_top.u_apb_bfm.apb_read(8'h0C, rd);
        if (rd !== 32'h0) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R15: Empty RX read: exp=0 got=0x%08h", rd);
        end
        
        tb_top.u_apb_bfm.apb_read(8'h04, status);
        if (status[6]) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R15: RX_OVF set on empty read (must not be)");
        end

        // Test 3: TX write while EN=0 silently ignored
        $display("[TRACE] Test 3: TX write while EN=0 silently ignored");
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0);
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00AA);
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0003);
        tb_top.u_apb_bfm.apb_read(8'h04, status);
        if (!status[2]) begin // status[2] is TX_EMPTY
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] TX write when EN=0 was NOT ignored (TX_EMPTY=0)");
        end

        // Test 4: RX overflow (R14)
        $display("[TRACE] Test 4: RX overflow (R14)");
        tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_001F);
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001); // Assert SS
        
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00BB);
        end
        
        // Wait for 8 transfers to complete
        repeat (5000) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0 && rd[2] == 1'b1) break; // Wait until BUSY=0 and TX_EMPTY=1
        end
        
        // 9th transfer
        tb_top.u_apb_bfm.apb_write(8'h08, 32'h0000_00CC);
        repeat (1000) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);
            if (rd[0] == 1'b0 && rd[2] == 1'b1) break;
        end
        
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000); // Deassert SS

        tb_top.u_apb_bfm.apb_read(8'h04, status);
        if (!status[6]) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R14: RX_OVF not set after xfer to full RX FIFO");
        end
        
        tb_top.u_apb_bfm.apb_read(8'h1C, rd);
        coverage.sample_interrupts(rd[4:0], 5'h1F);
        if (!rd[3]) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R14: INT_STAT[RX_OVF] not set");
        end
        
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(8'h0C, rd);
        end
        tb_top.u_apb_bfm.apb_write(8'h1C, 32'h0000_001F);

        // Test 5: Reserved offsets read as 0 (R23)
        $display("[TRACE] Test 5: Reserved offsets read as 0 (R23)");
        tb_top.u_apb_bfm.apb_write(8'h24, 32'hDEAD_BEEF);
        tb_top.u_apb_bfm.apb_read(8'h24, rd);
        if (rd !== 32'h0) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R23: Reserved 0x24 = 0x%08h (exp 0)", rd);
        end
        
        tb_top.u_apb_bfm.apb_write(8'h30, 32'hCAFE_BABE);
        tb_top.u_apb_bfm.apb_read(8'h30, rd);
        if (rd !== 32'h0) begin
            ref_model.error_count++;
            $display("[SCOREBOARD_ERROR] R23: Reserved 0x30 = 0x%08h (exp 0)", rd);
        end

        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0);

        $display("\n==================================================================");
        $display("[INFO] error_injection_test: FINISHED");
        $display("==================================================================");
    endtask
endclass

`endif
