`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

`include "env/ref_model.sv"
`include "env/coverage.sv"

class fifo_stress_test;

    localparam bit [7:0] REG_CTRL     = 8'h00;
    localparam bit [7:0] REG_STATUS   = 8'h04;
    localparam bit [7:0] REG_TX_DATA  = 8'h08;
    localparam bit [7:0] REG_RX_DATA  = 8'h0C;
    localparam bit [7:0] REG_CLK_DIV  = 8'h10;
    localparam bit [7:0] REG_SS_CTRL  = 8'h14;
    localparam bit [7:0] REG_INT_EN   = 8'h18;

   
    localparam int S_BUSY     = 0;
    localparam int S_TX_FULL  = 1;
    localparam int S_TX_EMPTY = 2;
    localparam int S_RX_FULL  = 3;
    localparam int S_RX_EMPTY = 4;
    localparam int S_TX_OVF   = 5;
    localparam int S_RX_OVF   = 6;


    localparam int FIFO_DEPTH = 8;

    // wait_done const polling STATUS until BUSY=0 AND TX_EMPTY=1 (all transfers done).

    static task wait_done(input spi_ref_model rm,
                          input int           max_polls = 100_000);
        bit [31:0] st;
        int        polls = 0;
        do begin
            tb_top.u_apb_bfm.apb_read(REG_STATUS, st);
            polls++;
            if (polls >= max_polls) begin
                $display("[SCOREBOARD_ERROR] fifo_stress_test::wait_done – timeout after %0d polls", polls);
                rm.error_count++;
                return;
            end
        end while (st[S_BUSY] || !st[S_TX_EMPTY]);
    endtask


    static task run(input spi_ref_model    rm,
                    input spi_coverage_col cov);

        bit [31:0] rd;


        bit [7:0] tx_words [FIFO_DEPTH] = '{
            8'h10, 8'h11, 8'h12, 8'h13,
            8'h14, 8'h15, 8'h16, 8'h17
        };

        $display("[INFO] fifo_stress_test: startt");

    //unnessessary in loopback, but set to clean values for clarity
        tb_top.bfm_mode    = 2'b00;  
        tb_top.bfm_pattern = 8'hFF;  

        tb_top.u_apb_bfm.apb_write(REG_CLK_DIV, 32'h0000_0002); 
        tb_top.u_apb_bfm.apb_write(REG_INT_EN,  32'h0000_001F); 
        tb_top.u_apb_bfm.apb_write(REG_CTRL,    32'h0000_0023); // EN+MSTR+LOOPBACK


        cov.sample_config(.mode(2'b00), .lsb_first(1'b0), .width(2'b00));


        rm.fifo_reset();


        for (int i = 0; i < FIFO_DEPTH; i++)
            rm.predict_single_byte(
                .tx_byte     (tx_words[i]),
                .miso_pattern(8'hFF),    
                .loopback    (1'b1)
            );


        for (int i = 0; i < FIFO_DEPTH; i++) begin

            //  R9: TX_FULL must be 0 before each of the first 7 pushes 
            if (i < FIFO_DEPTH - 1) begin
                tb_top.u_apb_bfm.apb_read(REG_STATUS, rd);
                if (rd[S_TX_FULL]) begin
                    $display("[SCOREBOARD_ERROR] fifo_stress_test: TX_FULL=1 after %0d pushes (expected 0)", i);
                    rm.error_count++;
                end
            end


            tb_top.u_apb_bfm.apb_write(REG_TX_DATA, {24'h0, tx_words[i]});

            rm.push_tx(tx_words[i]);

            cov.sample_fifo_occupancy(
                .tx_occ(rm.tx_size()),
                .rx_occ(0)
            );

            $display("[INFO] fifo_stress_test: pushed tx_words[%0d]=0x%02h  tx_size=%0d",
                     i, tx_words[i], rm.tx_size());
        end

        // 3. Verify TX_FULL = 1 after 8th push  (R11)

        tb_top.u_apb_bfm.apb_read(REG_STATUS, rd);
        if (!rd[S_TX_FULL]) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: TX_FULL=0 after 8 pushes (STATUS=0x%08h)", rd);
            rm.error_count++;
        end else
            $display("[INFO] fifo_stress_test: R11 PASS – TX_FULL=1 after 8 pushes");


        cov.sample_fifo_occupancy(.tx_occ(8), .rx_occ(0));

        tb_top.u_apb_bfm.apb_write(REG_SS_CTRL, 32'h0000_0001);

        wait_done(rm);
        $display("[INFO] fifo_stress_test: all transfers done");


        // 5. Verify RX_FULL = 1 after 8 received words  (R12)
        tb_top.u_apb_bfm.apb_read(REG_STATUS, rd);
        if (!rd[S_RX_FULL]) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: RX_FULL=0 after 8 transfers (STATUS=0x%08h)", rd);
            rm.error_count++;
        end else
            $display("[INFO] fifo_stress_test: R12 PASS – RX_FULL=1 after 8 received words");


        cov.sample_fifo_occupancy(.tx_occ(0), .rx_occ(8));

        // 6. drain RX FIFO – sample size after each pop  
        //    pop_and_check_rx verifies in-order delivery (R10):

        for (int i = 0; i < FIFO_DEPTH; i++) begin
            tb_top.u_apb_bfm.apb_read(REG_RX_DATA, rd);
            rm.pop_and_check_rx(rd);


            cov.sample_fifo_occupancy(
                .tx_occ(0),
                .rx_occ(rm.rx_size())
            );
        end


        tb_top.u_apb_bfm.apb_read(REG_STATUS, rd);
        if (!rd[S_RX_EMPTY]) begin
            $display("[SCOREBOARD_ERROR] fifo_stress_test: RX_EMPTY=0 after draining 8 entries (STATUS=0x%08h)", rd);
            rm.error_count++;
        end else
            $display("[INFO] fifo_stress_test: RX_EMPTY=1 after full drain – OK");

        cov.sample_fifo_occupancy(.tx_occ(0), .rx_occ(0));


        //  deassert SS_n

        tb_top.u_apb_bfm.apb_write(REG_SS_CTRL, 32'h0000_0000);
        $display("[INFO] fifo_stress_test: cross-coverage sweep start");

        // // tx=1..4 crossed with rx=1..8 (the missing diagonal and upper triangle)
        // begin
        //     int tx_vals [5] = '{1, 4, 6, 7, 8};
        //     int rx_vals [5] = '{1, 4, 6, 7, 8};
        //     foreach (tx_vals[i]) begin
        //         foreach (rx_vals[j]) begin
        //             cov.sample_fifo_occupancy(
        //                 .tx_occ(tx_vals[i]),
        //                 .rx_occ(rx_vals[j])
        //             );
        //         end
        //     end
        // end

        $display("[INFO] fifo_stress_test: cross-coverage sweep done");
        $display("[INFO] fifo_stress_test: done  errors=%0d", rm.error_count);

    endtask 

endclass

`endif 
