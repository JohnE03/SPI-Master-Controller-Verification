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

    localparam int FIFO_DEPTH = 8;
    // Running error count. tb_top reads this to emit the final
    // [TEST_PASSED]/[TEST_FAILED] line.
    int error_count = 0;

    // Minimal predictor state. Only the pieces the sanity_test exercises
    // are modelled; students should fill in the rest.
    bit [7:0]  pred_rx_byte;
    bit [7:0]  pred_tx_byte;
    
    bit [4:0] shadow_int_stat = 5'b0;
    bit [4:0] shadow_int_en   = 5'b0;


    bit [7:0] tx_queue [$];   
    bit [7:0] rx_queue [$];   

    // sticky overflow flags 
    //for member 5 (3my moaz)
    bit tx_ovf_predicted = 1'b0;
    bit rx_ovf_predicted = 1'b0;

    function new();
        error_count  = 0;
        pred_rx_byte = 8'h0;
        pred_tx_byte = 8'h0;
        tx_ovf_predicted = 1'b0;
        rx_ovf_predicted = 1'b0;
    endfunction
    // fifo_reset
    //   wipe both queues and sticky flags.
    function void fifo_reset();
        tx_queue.delete();
        rx_queue.delete();
        tx_ovf_predicted = 1'b0;
        rx_ovf_predicted = 1'b0;
    endfunction

    function bit tx_full();  return (tx_queue.size() >= FIFO_DEPTH); endfunction
    function bit rx_full();  return (rx_queue.size() >= FIFO_DEPTH); endfunction
    function bit tx_empty(); return (tx_queue.size() == 0);          endfunction
    function bit rx_empty(); return (rx_queue.size() == 0);          endfunction
    function int tx_size();  return tx_queue.size();                  endfunction
    function int rx_size();  return rx_queue.size();                  endfunction

// main pushing function for the tx_queue model.
    function void push_tx(input bit [7:0] data);
        if (tx_full()) begin
            tx_ovf_predicted = 1'b1;
            $display("[REF_MODEL] push_tx: TX FIFO full – 0x%02h discarded (TX_OVF predicted)", data);
        end else begin
            tx_queue.push_back(data);
            $display("[REF_MODEL] push_tx: enqueued 0x%02h  tx_size=%0d", data, tx_queue.size());
        end
    endfunction


    task predict_single_byte(input bit [7:0] tx_byte,
                             input bit [7:0] miso_pattern,
                             input bit       loopback);
        bit [7:0] expected_rx;

        // legacy scalar (sanity_test path) 
        pred_tx_byte = tx_byte;
        expected_rx  = loopback ? tx_byte : miso_pattern;
        pred_rx_byte = expected_rx;

        //  model DUT's automatic RX-FIFO push on transfer completion 
        if (rx_full()) begin
            // R14: transfer completes while RX_FULL → word discarded, RX_OVF set
            rx_ovf_predicted = 1'b1;
            $display("[REF_MODEL] predict_single_byte: RX FIFO full – 0x%02h discarded (RX_OVF predicted)", expected_rx);
        end else begin
            rx_queue.push_back(expected_rx);
            $display("[REF_MODEL] predict_single_byte: RX enqueued 0x%02h  rx_size=%0d", expected_rx, rx_queue.size());
        end
    endtask

    task pop_and_check_rx(input bit [31:0] observed);
        bit [7:0] obs8 = observed[7:0];
        bit [7:0] exp8;

        if (rx_empty()) begin
            // R15: read while empty → hardware returns 0x00, no error flag
            exp8 = 8'h00;
            if (obs8 !== exp8) begin
                $display("[SCOREBOARD_ERROR] pop_and_check_rx (empty): expected=0x%02h observed=0x%02h",
                         exp8, obs8);
                error_count++;
            end else
                $display("[REF_MODEL] pop_and_check_rx (empty): PASS 0x00 – R15 OK");
        end else begin
            exp8 = rx_queue.pop_front();
            if (obs8 !== exp8) begin
                $display("[SCOREBOARD_ERROR] pop_and_check_rx: expected=0x%02h observed=0x%02h",
                         exp8, obs8);
                error_count++;
            end else
                $display("[REF_MODEL] pop_and_check_rx: PASS 0x%02h  rx_size=%0d", obs8, rx_queue.size());
        end
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
