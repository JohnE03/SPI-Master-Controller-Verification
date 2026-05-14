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

    // Tracking what the CPU wrote to each of the 9 APB registers
    bit [31:0] shadow_ctrl     = 32'h0;
    bit [31:0] shadow_status   = 32'h14;
    bit [31:0] shadow_tx_data  = 32'h0;
    bit [31:0] shadow_rx_data  = 32'h0;
    bit [31:0] shadow_clk_div  = 32'h0;
    bit [31:0] shadow_ss_ctrl  = 32'h0;
    bit [31:0] shadow_int_en = 32'h0;
    bit [31:0] shadow_int_stat = 32'h0;
    bit [31:0] shadow_delay    = 32'h0;


    bit [7:0] tx_queue [$];   
    bit [7:0] rx_queue [$];
    // sticky overflow flags 
    //for member 5
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
            // --- MEMBER 5 INTEGRATION: TX Overflow (R13) ---
            tx_ovf_predicted = 1'b1;
            shadow_status[5]   = 1'b1; // TX_OVF in status register
            shadow_int_stat[2] = 1'b1; // INT_STAT[TX_OVF] interrupt triggered
            
            $display("[REF_MODEL] push_tx: TX FIFO full - 0x%02h discarded (TX_OVF predicted)", data);
        end else begin
            tx_queue.push_back(data);
            shadow_status[2] = 1'b0; // Clear TX_EMPTY
            if (tx_queue.size() == FIFO_DEPTH)
                shadow_status[1] = 1'b1; // Set TX_FULL
                
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
        // model DUT's automatic RX-FIFO push on transfer completion 
        if (rx_full()) begin
            // --- MEMBER 5 INTEGRATION: RX Overflow (R14) ---
            rx_ovf_predicted = 1'b1;
            shadow_status[6]   = 1'b1; // RX_OVF in status register (Assuming bit 6)
            shadow_int_stat[3] = 1'b1; // INT_STAT[RX_OVF] interrupt triggered (Assuming bit 3)
            
            $display("[REF_MODEL] predict_single_byte: RX FIFO full - 0x%02h discarded (RX_OVF predicted)", expected_rx);
        end else begin
            rx_queue.push_back(expected_rx);
            shadow_status[4] = 1'b0; // Clear RX_EMPTY
            if (rx_queue.size() == FIFO_DEPTH)
                shadow_status[3] = 1'b1; // Set RX_FULL
                
            $display("[REF_MODEL] predict_single_byte: RX enqueued 0x%02h  rx_size=%0d", expected_rx, rx_queue.size());
        end
    endtask

  task pop_and_check_rx(input bit [31:0] observed);
        bit [7:0] obs8 = observed[7:0];
        bit [7:0] exp8;
        if (rx_empty()) begin
            // --- MEMBER 5 INTEGRATION: Empty Read (R15) ---
            // R15: read while empty -> hardware returns 0x00, no error flag or OVF
            exp8 = 8'h00;
            if (obs8 !== exp8) begin
                $display("[SCOREBOARD_ERROR] pop_and_check_rx (empty): expected=0x%02h observed=0x%02h", exp8, obs8);
                error_count++;
            end else
                $display("[REF_MODEL] pop_and_check_rx (empty): PASS 0x00 - R15 OK");
        end else begin
            exp8 = rx_queue.pop_front();
            // Update shadow status on pop
            if (rx_empty()) begin
                shadow_status[4] = 1'b1; // Set RX_EMPTY
                shadow_status[3] = 1'b0; // Clear RX_FULL
            end
            
            if (obs8 !== exp8) begin
                $display("[SCOREBOARD_ERROR] pop_and_check_rx: expected=0x%02h observed=0x%02h", exp8, obs8);
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

    function void predict_transfer_time(bit [1:0] width, bit [15:0] clk_div);
        int total_bits;
        int expected_pclks;
        
        if (width == 2'b00) total_bits = 8;
        else if (width == 2'b01) total_bits = 16;
        else total_bits = 32;

        // Formula: SCLK period = 2 * (CLK_DIV + 1) PCLKs.
        // Total time = SCLK period * total bits.
        expected_pclks = total_bits * 2 * (int'(clk_div) + 1);
        $display("[SCOREBOARD] Prediction: Transfer should take exactly %0d PCLK cycles (Width=%0d bits, DIV=%0d)", 
                 expected_pclks, total_bits, clk_div);
    endfunction
    // flush_test
    task predict_flush();
        // Rule R3: When EN drops to 0, FIFOs and shifter are held in reset.
        // NOTE FOR MEMBER 4: When you add your queues, add tx_queue.delete() 
        // and rx_queue.delete() inside this task!
        pred_tx_byte = 8'h0;
        pred_rx_byte = 8'h0;
        $display("[INFO] Scoreboard: Flush predicted (CTRL.EN dropped to 0).");
    endtask

endclass

`endif // SPI_REF_MODEL_SV
