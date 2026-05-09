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

        #200;

        tb_top.u_apb_bfm.apb_write(APB_CTRL,    32'h0000_0003);
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'h0000_0004);
        tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_001F);
        ref_model.update_shadow_regs(APB_INT_EN, 32'h0000_001F);

        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001); 

        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: TX Empty check = %b", rd_data[0]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        $display("[INFO] interrupt_test: Filling RX FIFO to trigger RX Full...");
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_BBBB);
            repeat (500) begin
                tb_top.u_apb_bfm.apb_read(APB_STATUS, rd_data);
                if (rd_data[0] == 1'b0) break;
            end
        end
        
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: RX Full/TC check = %b", rd_data[4:0]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        $display("[INFO] interrupt_test: Triggering RX Overrun...");
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hCCCC_DDDD);
        repeat (500) begin
            tb_top.u_apb_bfm.apb_read(APB_STATUS, rd_data);
            if (rd_data[0] == 1'b0) break;
        end
        
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        $display("[INFO] interrupt_test: RX Overrun check = %b", rd_data[3]);
        coverage.sample_interrupts(rd_data[4:0], 5'b11111);

        $display("[INFO] interrupt_test: Initiating Race Condition Attack...");
        for (int i = 0; i < 9; i++) begin
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h0000_00AA);
        end

        fork
            begin
                tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F); 
            end
            begin
                @(posedge tb_top.apb.cb_master.penable);
                #1; 
                force tb_top.u_wrap.u_dut.u_regfile.int_stat[2] = 1'b1; 
                #10;
                release tb_top.u_wrap.u_dut.u_regfile.int_stat[2];
            end
        join

        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, rd_data);
        ref_model.shadow_int_stat = rd_data[4:0];
        ref_model.check_irq_pin(tb_top.u_wrap.u_dut.u_regfile.IRQ);

        if (rd_data[2] == 0) begin
            $display("[SCOREBOARD_ERROR] R18 Violation! Bit cleared during a race!");
            ref_model.error_count++;
        end else begin
            $display("[INFO] interrupt_test: Race Condition survived!");
        end

        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

        $display("[INFO] interrupt_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif