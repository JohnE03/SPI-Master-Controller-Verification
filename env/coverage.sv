// =============================================================================
// coverage.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal functional-coverage collector built on covergroups. Students must
// extend this to hit the 85% functional-coverage gate in the grading rubric.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    bit [1:0] cv_mode;
    bit       cv_lsb_first;
    bit [1:0] cv_width;

    bit [4:0] cv_int_stat;
    bit [4:0] cv_int_en;

    bit [3:0] cv_tx_occ;
    bit [3:0] cv_rx_occ;

    covergroup cg_config;
        option.per_instance = 1;
        cp_mode : coverpoint cv_mode  {
            bins modes[] = {[0:3]};
        }
        cp_first : coverpoint cv_lsb_first {
            bins msb_first = {0};
            bins lsb_first = {1};
        }
        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        }
        cx_mode_width : cross cp_mode, cp_width;
    endgroup

    covergroup cg_interrupts;
        option.per_instance = 1;
        cp_stat : coverpoint cv_int_stat;
        cp_en   : coverpoint cv_int_en;
        
        cx_stat_en : cross cp_stat, cp_en; 
    endgroup

    covergroup cg_fifo_occupancy;
        option.per_instance = 1;

        cp_tx_occ : coverpoint cv_tx_occ {
            bins tx_empty       = {4'd0};   
            bins tx_one         = {4'd1};   
            bins tx_mid         = {4'd4};   
            bins tx_almost_full = {4'd7};   
            bins tx_full        = {4'd8};   
            bins tx_other       = default;
        }

        cp_rx_occ : coverpoint cv_rx_occ {
            bins rx_empty       = {4'd0};
            bins rx_one         = {4'd1};
            bins rx_mid         = {4'd4};
            bins rx_almost_full = {4'd7};
            bins rx_full        = {4'd8};   
            bins rx_other       = default;
        }

        cx_tx_rx_occ : cross cp_tx_occ, cp_rx_occ;
    endgroup

    function new();
        cg_config = new();
        cg_interrupts = new();
        cg_fifo_occupancy = new();
    endfunction

    task sample_config(input bit [1:0] mode,
                       input bit       lsb_first,
                       input bit [1:0] width);
        cv_mode      = mode;
        cv_lsb_first = lsb_first;
        cv_width     = width;
        cg_config.sample();
    endtask

    task sample_interrupts(input bit [4:0] int_stat, input bit [4:0] int_en);
        cv_int_stat = int_stat;
        cv_int_en   = int_en;
        cg_interrupts.sample();
    endtask

    task sample_fifo_occupancy(input bit [3:0] tx_occ, input bit [3:0] rx_occ);
        cv_tx_occ = tx_occ;
        cv_rx_occ = rx_occ;
        cg_fifo_occupancy.sample();
    endtask

endclass

`endif // SPI_COVERAGE_COL_SV
