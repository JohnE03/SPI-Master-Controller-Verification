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

    function new();
        cg_config = new();
        cg_interrupts = new();
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

endclass

`endif // SPI_COVERAGE_COL_SV
