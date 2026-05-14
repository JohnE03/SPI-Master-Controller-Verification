// =============================================================================
// spi_sva.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// SVA target module. `tb_top` binds it into `dut_wrapper.u_dut.u_regfile`:
//
//   bind u_wrap.u_dut.u_regfile spi_sva u_sva (.*);
//   (use the instance path of your dut_wrapper instance, here `u_wrap`)
//
// Add assertions for every spec requirement that you can prove without
// modifying the DUT. The scaffold ships two starter assertions so that the
// file compiles and the grader sees at least one SVA active.
// =============================================================================

`ifndef SPI_SVA_SV
`define SPI_SVA_SV
`timescale 1ns/1ps

module spi_sva (
    input wire        PCLK,
    input wire        PRESETn,
    input wire        ctrl_en,
    input wire [4:0]  int_stat,
    input wire [4:0]  int_en,
    input wire        IRQ
);

   


    // Aggregate IRQ is OR of all five sticky status bits (R16)
    a_irq_agg : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            IRQ == |(int_stat & int_en)
    ) else begin
        $error("[ASSERTION_ERROR] a_irq_agg IRQ=%b int_stat=%b",
                  IRQ, int_stat);
    tb_top.assertion_error_count = tb_top.assertion_error_count + 1; //   assertion failure then TEST_FAILED
    end
    // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    // (student should extend with the exact spec wording from R19)
    a_irq_off_when_disabled : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (!ctrl_en) |-> ##[0:1] (IRQ == 1'b0 || int_stat != 0)
    ) else begin
    $error("[ASSERTION_ERROR] a_irq_off_when_disabled");
    tb_top.assertion_error_count = tb_top.assertion_error_count + 1;
    end

    
    // R5: MOSI must be stable for at least 1 PCLK around the sample edge.
    // We determine the sample edge based on CPOL (cfg_mode[1]) and CPHA (cfg_mode[0]).
    // Since this SVA is bound to u_regfile, we use absolute hierarchical paths to reach u_core.
    wire cpol = tb_top.u_wrap.u_dut.u_core.cfg_mode[1];
    wire cpha = tb_top.u_wrap.u_dut.u_core.cfg_mode[0];
 
    a_mosi_stability: assert property (
        @(posedge PCLK) disable iff (!PRESETn || !tb_top.u_wrap.u_dut.u_core.busy)
            (
                ((cpha == cpol) && $rose(tb_top.u_wrap.u_dut.u_core.SCLK)) ||
                ((cpha != cpol) && $fell(tb_top.u_wrap.u_dut.u_core.SCLK))
            ) |-> $stable(tb_top.u_wrap.u_dut.u_core.MOSI)
    ) else begin
    $error("[ASSERTION_ERROR] a_mosi_stability: MOSI changed during sample edge!");
    tb_top.assertion_error_count = tb_top.assertion_error_count + 1; //   assertion failure then TEST_FAILED
    end


    // Placeholders - Adjust these to match your actual register map parameters
     localparam [7:0] TX_DATA_ADDR = 8'h08;
     localparam [7:0] RX_DATA_ADDR = 8'h0C;
     localparam        BIT_TX_OVF   = 2;
     localparam        BIT_RX_OVF   = 3;
     logic transfer_complete; // e.g., $fell(busy)

    // R13: TX Overflow
    a_req13_tx_ovf : assert property (
        @(posedge PCLK) disable iff (PRESETn !== 1'b1)
            (PSEL && PENABLE && PWRITE && (PADDR == TX_DATA_ADDR) && tx_full && PREADY) |=> 
            (status[BIT_TX_OVF] == 1'b1) && (int_stat[BIT_TX_OVF] == 1'b1)
    ) else $error("[ASSERTION_ERROR] a_req13_tx_ovf: Writing to TX_DATA while TX_FULL=1 failed to set TX_OVF flags.");

    // R14: RX Overflow
    a_req14_rx_ovf : assert property (
        @(posedge PCLK) disable iff (PRESETn !== 1'b1)
            (transfer_complete && rx_full) |=> 
            (status[BIT_RX_OVF] == 1'b1) && (int_stat[BIT_RX_OVF] == 1'b1)
    ) else $error("[ASSERTION_ERROR] a_req14_rx_ovf: Transfer completing while RX_FULL=1 failed to set RX_OVF flags.");

    // R15: Read Empty RX_DATA
    // Part A: Returns 0 on the APB bus during the active read phase
    a_req15_rx_empty_read_data : assert property (
        @(posedge PCLK) disable iff (PRESETn !== 1'b1)
            (PSEL && PENABLE && !PWRITE && (PADDR == RX_DATA_ADDR) && rx_empty && PREADY) |-> 
            (PRDATA == 32'h0)
    ) else $error("[ASSERTION_ERROR] a_req15_rx_empty_read_data: Reading RX_DATA while RX_EMPTY did not return 0.");

    // Part B: Does NOT set the RX_OVF flag (flags should remain unchanged/untriggered)
    a_req15_rx_empty_read_no_ovf : assert property (
        @(posedge PCLK) disable iff (PRESETn !== 1'b1)
            (PSEL && PENABLE && !PWRITE && (PADDR == RX_DATA_ADDR) && rx_empty && PREADY) |=> 
            !$rose(status[BIT_RX_OVF]) && !$rose(int_stat[BIT_RX_OVF])
    ) else $error("[ASSERTION_ERROR] a_req15_rx_empty_read_no_ovf: Reading RX_DATA while RX_EMPTY incorrectly triggered an RX_OVF.");

    // R8/R25: SCLK half-period must be CLK_DIV + 1 PCLKs.
    // R25: CLK_DIV must be sampled at transfer start and held for that transfer.

logic [16:0] sclk_cnt;
logic        sclk_prev;
logic        seen_first_edge;
logic [15:0] sampled_div; //  sampled DIV for current transfer

wire is_busy  = tb_top.u_wrap.u_dut.u_core.busy;
wire sclk_pin = tb_top.u_wrap.u_dut.u_core.SCLK;
wire [15:0] live_div = tb_top.u_wrap.u_dut.u_core.cfg_clk_div;

always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        sclk_cnt        <= 0;
        sclk_prev       <= 0;
        seen_first_edge <= 0;
        sampled_div     <= 0;
    end
    else begin
        sclk_prev <= sclk_pin;

        if (!is_busy) begin
            sclk_cnt        <= 0;
            seen_first_edge <= 0;
            sampled_div     <= live_div; // ready for next transfer
        end
        else begin
            
            if (!seen_first_edge)
                sampled_div <= live_div;

            if (sclk_pin != sclk_prev) begin
                sclk_cnt        <= 1;
                seen_first_edge <= 1;
            end
            else begin
                sclk_cnt <= sclk_cnt + 1;
            end
        end
    end
end

// Check SCLK toggle spacing using sampled_div, not live_div.
// This allows R25 mid-transfer CLK_DIV writes without false assertion failures.
a_sclk_frequency: assert property (
    @(posedge PCLK) disable iff (!PRESETn || !is_busy || !seen_first_edge)
        (sclk_pin != sclk_prev) |-> (sclk_cnt == sampled_div + 1)
) else begin 
$error("[ASSERTION_ERROR] a_sclk_frequency: SCLK wrong half-period. Counted=%0d expected=%0d sampled_div=%0d live_div=%0d",
              sclk_cnt, sampled_div + 1, sampled_div, live_div);

    tb_top.assertion_error_count = tb_top.assertion_error_count + 1; //   assertion failure then TEST_FAILED
end

// R25: sampled transfer configuration must stay stable during active transfer  


a_r25_xfer_config_stable:
assert property (
    @(posedge PCLK) disable iff (!PRESETn)
    (is_busy && $past(is_busy)) |-> $stable({
        tb_top.u_wrap.u_dut.u_core.xfer_mode,
        tb_top.u_wrap.u_dut.u_core.xfer_lsb_first,
        tb_top.u_wrap.u_dut.u_core.xfer_width,
        tb_top.u_wrap.u_dut.u_core.xfer_div
    })
) else begin
    $error("[ASSERTION_ERROR] R25 xfer config changed during active transfer");
    tb_top.assertion_error_count = tb_top.assertion_error_count + 1;
    end

// R21: If DELAY > 0 and TX FIFO is not empty,
// FSM should enter S_GAP shortly after S_FINISH.
// Allow 0-2 extra cycles because RTL may have pipeline timing.
 
property p_r21_delay_state;
    @(posedge PCLK) disable iff (!PRESETn)
    (tb_top.u_wrap.u_dut.u_core.state == 2 &&
     !tb_top.u_wrap.u_dut.u_core.tx_empty &&
      tb_top.u_wrap.u_dut.u_core.cfg_delay > 0)
    |=> ##[0:2] (tb_top.u_wrap.u_dut.u_core.state == 3);
endproperty
 
a_r21_delay_state: assert property(p_r21_delay_state)
else begin
    $error("[ASSERTION_ERROR] a_r21_delay_state: FSM did not enter S_GAP shortly after S_FINISH when DELAY > 0 and TX queued");
    tb_top.assertion_error_count = tb_top.assertion_error_count + 1;
end

endmodule

`endif // SPI_SVA_SV
