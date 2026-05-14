`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV

class reg_access_test;
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        bit [31:0] rd_data;
        
        // Random data variables
        bit [31:0] w_ctrl, w_clk_div, w_ss_ctrl, w_int_en, w_delay;

        // Register Addresses
        localparam [7:0] CTRL     = 8'h00;
        localparam [7:0] STATUS   = 8'h04;
        localparam [7:0] TX_DATA  = 8'h08;
        localparam [7:0] RX_DATA  = 8'h0C;
        localparam [7:0] CLK_DIV  = 8'h10;
        localparam [7:0] SS_CTRL  = 8'h14;
        localparam [7:0] INT_EN   = 8'h18;
        localparam [7:0] INT_STAT = 8'h1C;
        localparam [7:0] DELAY    = 8'h20;

        $display("\n==================================================================");
        $display("[INFO] reg_access_test: STARTING");
        $display("==================================================================");

        // ------------------------------------------------------------------
        // Step 1: Check Reset Values
        // ------------------------------------------------------------------
        $display("[TRACE] Step 1: Checking Hardware Reset Values");
        tb_top.u_apb_bfm.apb_read(CTRL, rd_data);     ref_model.check_reg("CTRL",     32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(STATUS, rd_data);   ref_model.check_reg("STATUS",   32'h1, rd_data); // TX_EMPTY bit is 1
        tb_top.u_apb_bfm.apb_read(TX_DATA, rd_data);  ref_model.check_reg("TX_DATA",  32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(RX_DATA, rd_data);  ref_model.check_reg("RX_DATA",  32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(CLK_DIV, rd_data);  ref_model.check_reg("CLK_DIV",  32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(SS_CTRL, rd_data);  ref_model.check_reg("SS_CTRL",  32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(INT_EN, rd_data);   ref_model.check_reg("INT_EN",   32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(INT_STAT, rd_data); ref_model.check_reg("INT_STAT", 32'h0, rd_data);
        tb_top.u_apb_bfm.apb_read(DELAY, rd_data);    ref_model.check_reg("DELAY",    32'h0, rd_data);

        // ------------------------------------------------------------------
        // Step 2: Write Random Data to R/W Registers
        // ------------------------------------------------------------------
        $display("[TRACE] Step 2: Poking R/W Registers with Random Data");
        
        // Generate random data mapped to the valid bit-widths of each register
        w_ctrl    = $urandom() & 32'h0000_00FE; // Mask bit 0 (EN) to 0 so we don't start SPI
        w_clk_div = $urandom() & 32'h0000_FFFF; 
        w_ss_ctrl = $urandom() & 32'h0000_00FF; 
        w_int_en  = $urandom() & 32'h0000_001F; 
        w_delay   = $urandom() & 32'h0000_00FF; 

        tb_top.u_apb_bfm.apb_write(CTRL, w_ctrl);
        tb_top.u_apb_bfm.apb_write(CLK_DIV, w_clk_div);
        tb_top.u_apb_bfm.apb_write(SS_CTRL, w_ss_ctrl);
        tb_top.u_apb_bfm.apb_write(INT_EN, w_int_en);
        tb_top.u_apb_bfm.apb_write(DELAY, w_delay);

        // ------------------------------------------------------------------
        // Step 3: Read Back to Verify Retention
        // ------------------------------------------------------------------
        $display("[TRACE] Step 3: Reading Back to Verify Data Retention");
        tb_top.u_apb_bfm.apb_read(CTRL, rd_data);     ref_model.check_reg("CTRL",     w_ctrl, rd_data);
        tb_top.u_apb_bfm.apb_read(CLK_DIV, rd_data);  ref_model.check_reg("CLK_DIV",  w_clk_div, rd_data);
        tb_top.u_apb_bfm.apb_read(SS_CTRL, rd_data);  ref_model.check_reg("SS_CTRL",  w_ss_ctrl, rd_data);
        tb_top.u_apb_bfm.apb_read(INT_EN, rd_data);   ref_model.check_reg("INT_EN",   w_int_en, rd_data);
        tb_top.u_apb_bfm.apb_read(DELAY, rd_data);    ref_model.check_reg("DELAY",    w_delay, rd_data);

        $display("\n==================================================================");
        $display("[INFO] reg_access_test: FINISHED");
        $display("==================================================================");
    endtask
endclass
`endif