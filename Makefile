# =============================================================================
# Makefile - SV-only starter scaffold for the SPI Master Verification Project
# =============================================================================

SIMULATOR ?= questa
SEED      ?= 0
TEST      ?= sanity_test
WAVES     ?= 0

# Resolve the project root from this file's location.
# harness/examples/sv_only/Makefile  -> ../../..
PROJ_ROOT  ?= ../../..
HARNESS    ?= $(PROJ_ROOT)/harness
STUDENT_TB ?= .

# DUT sources. Grader overrides DUT_SRCS.
DUT_SRCS   ?= \
  $(PROJ_ROOT)/golden_rtl/spi_core.sv \
  $(PROJ_ROOT)/golden_rtl/apb_regfile.sv \
  $(PROJ_ROOT)/golden_rtl/spi_master.sv

DUT_SRC    ?=
EFF_DUT_SRCS = $(if $(strip $(DUT_SRC)),$(DUT_SRC),$(DUT_SRCS))

BONUS_TEST ?= ral_hw_reset_test

# ---- student source lists ---------------------------------------------------

TB_SRCS    ?= \
  $(STUDENT_TB)/tb/apb_master_bfm.sv \
  $(STUDENT_TB)/tb/spi_slave_bfm.sv \
  $(STUDENT_TB)/tb/tb_top.sv

ENV_SRCS   ?= \
  $(STUDENT_TB)/env/ref_model.sv \
  $(STUDENT_TB)/env/coverage.sv

SEQ_SRCS   ?= \
  $(STUDENT_TB)/sequences/stim_lib.sv

ASSERT_SRCS?= \
  $(STUDENT_TB)/assertions/spi_sva.sv

INC_DIRS   ?= +incdir+$(HARNESS) +incdir+$(STUDENT_TB) \
              +incdir+$(STUDENT_TB)/env +incdir+$(STUDENT_TB)/tb \
              +incdir+$(STUDENT_TB)/sequences +incdir+$(STUDENT_TB)/tests

# ---- regression list --------------------------------------------------------

REGRESSION_TESTS = \
  sanity_test \
  reg_access_test \
  mode_coverage_test \
  width_coverage_test \
  fifo_stress_test \
  interrupt_test \
  clk_div_corner_test \
  loopback_test \
  delay_transfer_test \
  error_injection_test \
  flush_test \
  randomized_sanity_test

REGRESSION_SEEDS ?= 5

# ============================================================================
# Questa flow
# ============================================================================

ifeq ($(SIMULATOR),questa)

# Keep +acc off by default for speed.
# Add it only if you really need deep waveform/debug access.
VLOG_FLAGS  = -sv -timescale=1ns/1ps +define+SIM $(INC_DIRS)
COV_FLAG    = +cover=bcestf

compile:
	@mkdir -p build
	vlib work
	vlog $(VLOG_FLAGS) $(COV_FLAG) \
	   $(HARNESS)/apb_if.sv \
	   $(HARNESS)/spi_if.sv \
	   $(ENV_SRCS) \
	   $(SEQ_SRCS) \
	   $(EFF_DUT_SRCS) \
	   $(HARNESS)/dut_wrapper.sv \
	   $(ASSERT_SRCS) \
	   $(TB_SRCS)

# Normal single-test run.
# This keeps the required interface working:
# make run TEST=<name> SEED=<n>
run: compile
	vsim -c -coverage work.tb_top \
	     -do "coverage save -onexit cov_$(TEST)_$(SEED).ucdb; run -all; quit -f" \
	     +TESTNAME=$(TEST) +UVM_TESTNAME=$(TEST) +SEED=$(SEED) \
	     $(if $(filter 1,$(WAVES)), -wlf waves_$(TEST)_$(SEED).wlf,)

# Regression-only run.
# Does NOT call compile, so make regress does not recompile for every seed.
run_nocompile:
	vsim -c -coverage work.tb_top \
	     -do "coverage save -onexit cov_$(TEST)_$(SEED).ucdb; run -all; quit -f" \
	     +TESTNAME=$(TEST) +UVM_TESTNAME=$(TEST) +SEED=$(SEED) \
	     $(if $(filter 1,$(WAVES)), -wlf waves_$(TEST)_$(SEED).wlf,)

run_bonus: compile
	vsim -c work.tb_top -do "run -all; quit -f" \
	     +TESTNAME=$(BONUS_TEST) +UVM_TESTNAME=$(BONUS_TEST) +SEED=$(SEED)

define REGRESS_ONE
	echo "=== Running $(1) for $(REGRESSION_SEEDS) seeds ===" ; \
	for s in `seq 1 $(REGRESSION_SEEDS)` ; do \
		"$(MAKE)" -s run_nocompile TEST=$(1) SEED=$$s WAVES=0 \
		  > build/log_$(1)_$$s.log 2>&1 ; \
	done ;
endef

# Grader calls make compile first, then make regress.
# This target still depends on compile, but it compiles only once,
# not once per test/seed.
regress: compile
	@mkdir -p build
	@rm -f cov_*.ucdb build/merged.ucdb
	@$(foreach t,$(REGRESSION_TESTS),$(call REGRESS_ONE,$(t)))
	-vcover merge -out build/merged.ucdb cov_*.ucdb

cov:
	@if [ -f build/merged.ucdb ]; then \
	    vcover report -details build/merged.ucdb > coverage_report.txt ; \
	    echo "Coverage report: coverage_report.txt" ; \
	else \
	    echo "No merged.ucdb - run 'make regress' first" ; exit 1 ; \
	fi

clean:
	rm -rf work build *.wlf *.vstf *.ucdb transcript coverage_report.txt

endif

.PHONY: compile run run_nocompile run_bonus regress cov clean