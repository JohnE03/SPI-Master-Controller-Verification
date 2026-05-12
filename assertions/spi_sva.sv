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




    // R8/R25: SCLK half-period must be CLK_DIV + 1 PCLKs.
    // R25: CLK_DIV must be sampled at transfer start and held for that transfer.

logic [16:0] sclk_cnt;
logic        sclk_prev;
logic        seen_first_edge;
logic [15:0] sampled_div; // added new: sampled DIV for current transfer

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
            sampled_div     <= live_div; // added new: ready for next transfer
        end
        else begin
            // added new: latch DIV at beginning of transfer
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

endmodule

`endif // SPI_SVA_SV