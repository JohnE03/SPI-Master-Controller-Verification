`ifndef INTERRUPT_TEST_SV
`define INTERRUPT_TEST_SV

class interrupt_test;

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [31:0] rd_data;

        localparam [7:0] APB_CTRL     = 8'h00;
        localparam [7:0] APB_STATUS   = 8'h04;
        localparam [7:0] APB_TX_DATA  = 8'h08;
        localparam [7:0] APB_RX_DATA  = 8'h0C;
        localparam [7:0] APB_CLK_DIV  = 8'h10;
        localparam [7:0] APB_SS_CTRL  = 8'h14;
        localparam [7:0] APB_INT_EN   = 8'h18;
        localparam [7:0] APB_INT_STAT = 8'h1C;

        $display("[INFO] interrupt_test: starting");

        // ---------------------------------------------------------
        // INITIALIZATION: Wait for reset and configure the Master
        // ---------------------------------------------------------
        #200;
        tb_top.u_apb_bfm.apb_write(APB_CTRL,    32'h0000_0003); // Enable SPI and Master mode
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004); // Set a fast clock divider
        tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_001F); // Unmute all 5 interrupt channels
        ref_model.update_shadow_regs(APB_INT_EN, 32'h0000_001F);

        // Assert Slave Select to begin interactions
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001); 

        // ---------------------------------------------------------
        // TX EMPTY CHECK
        // ---------------------------------------------------------
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: TX Empty check = %b", rd_data[0]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        // ---------------------------------------------------------
        // TRIGGER RX FULL
        // ---------------------------------------------------------
        $display("[INFO] interrupt_test: Filling RX FIFO to trigger RX Full...");
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_BBBB);
            // Poll STATUS.BUSY until each transfer completes
            repeat (500) begin
                tb_top.u_apb_bfm.apb_read(APB_STATUS, rd_data);
                if (rd_data[0] == 1'b0) break;
            end
        end
        
        // Verify the RX Full and Transfer Complete interrupts fired
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: RX Full/TC check = %b", rd_data[4:0]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        // ---------------------------------------------------------
        // TRIGGER RX OVERRUN: Push a 9th word into the full RX FIFO
        // ---------------------------------------------------------
        $display("[INFO] interrupt_test: Triggering RX Overrun: Push a 9th word into the full RX FIFO");
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hCCCC_DDDD); 
        repeat (500) begin
            tb_top.u_apb_bfm.apb_read(APB_STATUS, rd_data);
            if (rd_data[0] == 1'b0) break;
        end
        
        // Verify the RX Overrun interrupt fired (Bit 3)
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: RX Overrun check = %b", rd_data[3]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        // ---------------------------------------------------------
        // R17 W1C TRAP & CLEAR: Prove writing '0' does nothing, and '1' clears
        // ---------------------------------------------------------
        $display("[INFO] interrupt_test: Executing W1C Write-0 Trap...");
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0000); // Try to clear with 0s
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);        // Read back to check
        
        if (rd_data[3] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] W1C failed! Writing a 0 accidentally cleared the bit.");
            ref_model.error_count++;
        end else begin
            $display("[INFO] interrupt_test: Trap successful. Bit ignored the 0.");
        end

        // R17 FIX: REMOVE THE PHYSICAL ERROR BEFORE CLEARING
        $display("[INFO] interrupt_test: Reading APB_RX_DATA to relieve FIFO Overrun...");
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd_data); // Pulls one word out

        // Now drop the actual hammer to clear RX Overrun (Bit 3)
        $display("[INFO] interrupt_test: Executing W1C Write-1 Clear...");
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0008); 
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        if (rd_data[3] === 1'b1) begin
            $display("[SCOREBOARD_ERROR] W1C failed! Bit did not clear after writing 1.");
            ref_model.error_count++;
        end else begin
            $display("[INFO] interrupt_test: W1C successful! RX Overrun cleared.");
        end

        // ---------------------------------------------------------
        // R18 RACE CONDITION SETUP: Blast data to guarantee TX Overflow
        // ---------------------------------------------------------
        $display("[INFO] interrupt_test: Initiating Race Condition Attack...");
        for (int i = 0; i < 9; i++) begin
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00AA);
        end

        // ---------------------------------------------------------
        // Software Clear vs Hardware Set
        // ---------------------------------------------------------
        fork
            // Thread 1: Software tries to clear TX Overflow (Bit 2) by writing 32'h0000_0004
            begin
                tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0004); 
            end
            // Thread 2: Hardware snipes the TX Overflow bit (Bit 2) at the exact same time
            begin
                @(posedge tb_top.apb.cb_master.penable);
                #1; // 1ns delta-delay to ensure cycle-accurate alignment
                force tb_top.u_wrap.u_dut.u_regfile.int_stat[2] = 1'b1; // Hardware forces the error HIGH
                #10; // Hold the force for 1 clock cycle
                release tb_top.u_wrap.u_dut.u_regfile.int_stat[2];
            end
        join

        // ---------------------------------------------------------
        // RACE CONDITION VERIFICATION
        // ---------------------------------------------------------
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        ref_model.shadow_int_stat = rd_data[4:0];
        ref_model.check_irq_pin(tb_top.u_wrap.u_dut.u_regfile.IRQ);

        if (rd_data[2] == 0) begin
            $display("[SCOREBOARD_ERROR] R18 Violation! Bit cleared during a race!");
            ref_model.error_count++;
        end else begin
            $display("[INFO] interrupt_test: Race Condition survived!");
        end

        // Cleanup: Deassert Slave Select
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

        $display("[INFO] interrupt_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif