// =============================================================================
// spi_slave_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal SPI slave responder. Drives MISO with a configurable pattern that
// is rotated on every sampled SCLK edge. Students should extend this to
// capture the MOSI stream into a queue and expose it to their scoreboard.
//
// This BFM mirrors the SPI mode from the DUT's CTRL register via a shared
// testbench "mode" input. Students MUST keep it in lock-step with CTRL.MODE
// when writing new tests.
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave  spi,
    input  logic  [1:0]  mode,          // {CPOL, CPHA}
    input  logic  [31:0] miso_byte,     // Upgraded to 32-bit to support all widths
    input  logic  [1:0]  width,         // NEW: 00=8, 01=16, 10=32
    input  logic         lsb_first,     // NEW: 1=LSB-first, 0=MSB-first
    output logic  [31:0] captured_mosi  // NEW: exposes the MOSI stream to scoreboard
);

    logic sclk_q;   // SCLK previous value for edge detection
    logic [5:0] bit_cnt; // Replaces bit_idx to count up dynamically
    logic [31:0] shift_mosi; // Internal register to build the incoming MOSI word

    wire cpol  = mode[1];
    wire cpha  = mode[0];
    wire ss_act = (spi.ss_n != 4'hF);

    // Dynamic width decoding
    wire [5:0] total_bits = (width == 2'b00) ? 6'd8 :
                            (width == 2'b01) ? 6'd16 : 6'd32;

    // Mathematical Edge Detection
    wire sclk_rose = (sclk_q === 1'b0 && spi.sclk === 1'b1);
    wire sclk_fell = (sclk_q === 1'b1 && spi.sclk === 1'b0);

    wire leading_edge  = cpol ? sclk_fell : sclk_rose;
    wire trailing_edge = cpol ? sclk_rose : sclk_fell;

    wire sample_edge = cpha ? trailing_edge : leading_edge;
    wire launch_edge = cpha ? leading_edge : trailing_edge;

    // Shift Direction Logic
    wire [5:0] bit_idx = bit_cnt % total_bits;
    wire [5:0] target_bit = lsb_first ? bit_idx : (total_bits - 1 - bit_idx);

    initial begin
        spi.cb_slave.miso <= 1'b0;
        sclk_q  = 1'b0; // Will be set to cpol when idle
        bit_cnt = 0;
        captured_mosi = 0;
        shift_mosi = 0;
    end

    // MISO shifter. Upgraded to support all 4 modes, variable widths, and LSB/MSB
    always @(posedge spi.pclk) begin
        if (!ss_act) begin
            bit_cnt <= 0;
            shift_mosi <= 0;
            sclk_q <= cpol; // Lock SCLK tracker to CPOL to prevent false edge triggers
            
            // Mode handling: if CPHA=0, data must be on the line immediately when SS drops
            if (cpha == 1'b0) begin
                spi.cb_slave.miso <= lsb_first ? miso_byte[0] : miso_byte[total_bits - 1];
            end else begin
                spi.cb_slave.miso <= 1'b0;
            end
        end else begin
            // 1. Launch MISO Data
            if (launch_edge) begin
                spi.cb_slave.miso <= miso_byte[target_bit];
            end
            
            // 2. Sample MOSI Data
            if (sample_edge) begin
                // Place the bit in the correct location based on LSB/MSB
                if (lsb_first) 
                    shift_mosi[bit_idx] <= spi.mosi;
                else           
                    shift_mosi[(total_bits - 1) - bit_idx] <= spi.mosi;
                
                // If this is the final bit of the word, push it to the output port
                if (bit_idx == total_bits - 1) begin
                    if (lsb_first) begin
                        captured_mosi <= {shift_mosi[31:1], spi.mosi}; // Bypass trick for instant update
                    end else begin
                        captured_mosi <= {shift_mosi[31:1], spi.mosi} << (32 - total_bits); // Align depending on width
                        // A cleaner bypass for MSB:
                        captured_mosi[(total_bits - 1) - bit_idx] <= spi.mosi;
                        for(int i=0; i<32; i++) begin
                            if(i != ((total_bits - 1) - bit_idx)) captured_mosi[i] <= shift_mosi[i];
                        end
                    end
                end
                
                bit_cnt <= bit_cnt + 1;
            end
            
            sclk_q <= spi.sclk;
        end
    end

endmodule

`endif // SPI_SLAVE_BFM_SV
