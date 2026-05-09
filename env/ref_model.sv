// =============================================================================
// ref_model.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// A plain-SV reference model + scoreboard. It does not use UVM - it is a
// simple class that students instantiate from tb_top (`spi_ref_model u_ref =
// new();`) and update from their test programs.
//
// Students should extend this class to model the full spec: for the scaffold
// we model just enough to check the sanity_test.
// =============================================================================

`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // Running error count. tb_top reads this to emit the final
    // [TEST_PASSED]/[TEST_FAILED] line.
    int error_count = 0;

    // Minimal predictor state. Only the pieces the sanity_test exercises
    // are modelled; students should fill in the rest.
    bit [7:0]  pred_rx_byte;
    bit [7:0]  pred_tx_byte;
    
    bit [4:0] shadow_int_stat = 5'b0;
    bit [4:0] shadow_int_en   = 5'b0;

    function new();
        error_count  = 0;
        pred_rx_byte = 8'h0;
        pred_tx_byte = 8'h0;
    endfunction

    // Predict the result of a loopback OR of an externally-fed MISO byte.
    // For the scaffold we simply echo the byte we expect the slave BFM to
    // return. Real submissions should model the full SPI pipeline.
    task predict_single_byte(input bit [7:0] tx_byte,
                             input bit [7:0] miso_pattern,
                             input bit       loopback);
        pred_tx_byte = tx_byte;
        pred_rx_byte = loopback ? tx_byte : miso_pattern;
    endtask

    task check_rx(input bit [31:0] observed);
        bit [7:0] obs = observed[7:0];
        if (obs !== pred_rx_byte) begin
            $display("[SCOREBOARD_ERROR] RX byte mismatch: predicted=0x%02h observed=0x%02h",
                     pred_rx_byte, obs);
            error_count++;
        end
    endtask

    task check_reg(input string name,
                   input bit [31:0] expected,
                   input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            error_count++;
        end
    endtask

    task update_shadow_regs(input bit [7:0] address, input bit [31:0] write_data);
        if (address == 8'h18) begin 
            shadow_int_en = write_data[4:0];
            $display("[SCOREBOARD] Updated shadow_int_en to %b", shadow_int_en);
        end
    endtask

    function void check_irq_pin(bit actual_irq_pin);
        bit predicted_irq;
        
        predicted_irq = |(shadow_int_stat & shadow_int_en);
        
        if (actual_irq_pin !== predicted_irq) begin
            $display("[SCOREBOARD_ERROR] IRQ mismatch! Expected: %b, Got: %b", predicted_irq, actual_irq_pin);
            error_count++;
        end
    endfunction

endclass

`endif // SPI_REF_MODEL_SV
