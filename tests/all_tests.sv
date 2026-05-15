`ifndef ALL_TESTS_SV
`define ALL_TESTS_SV

class all_tests;

    static task automatic reset_between_tests(
        ref spi_ref_model ref_model
    );
        bit [31:0] dummy;

        $display("\n[ALL_TESTS] Resetting DUT and TB state between tests...");

        // Deassert SS and disable core before reset.
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000); // SS_CTRL
        tb_top.u_apb_bfm.apb_write(8'h00, 32'h0000_0000); // CTRL.EN=0

        repeat (5) @(posedge tb_top.PCLK);

        // Real DUT reset.
        tb_top.PRESETn = 1'b0;
        repeat (5) @(posedge tb_top.PCLK);
        tb_top.PRESETn = 1'b1;
        repeat (5) @(posedge tb_top.PCLK);

        // Clear common TB-side config.
        tb_top.bfm_mode      = 2'b00;
        tb_top.bfm_width     = 2'b00;
        tb_top.bfm_lsb_first = 1'b0;

        // Clear scoreboard model queues/state.
        ref_model.fifo_reset();

        // Optional: drain/read status once after reset.
        tb_top.u_apb_bfm.apb_read(8'h04, dummy);

        $display("[ALL_TESTS] Reset complete.\n");
    endtask


    static task run(
        ref spi_ref_model ref_model,
        ref spi_coverage_col coverage
    );
        int errors_before;
        int total_errors;

        total_errors = 0;

        $display("\n============================================================");
        $display("[ALL_TESTS] STARTING bundled regression in one vsim run");
        $display("============================================================");

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        sanity_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        reg_access_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        mode_coverage_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        width_coverage_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        fifo_stress_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        interrupt_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        clk_div_corner_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        loopback_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        delay_transfer_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        error_injection_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        flush_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);
        reset_between_tests(ref_model);

        // ------------------------------------------------------------
        errors_before = ref_model.error_count;
        randomized_sanity_test::run(ref_model, coverage);
        total_errors += (ref_model.error_count - errors_before);

        $display("\n============================================================");
        $display("[ALL_TESTS] FINISHED bundled regression");
        $display("[ALL_TESTS] Total scoreboard errors added = %0d", total_errors);
        $display("============================================================");
    endtask

endclass

`endif