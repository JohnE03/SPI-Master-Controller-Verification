# SPI Master Verification Environment (SV-Only)

## Overview

This repository contains a plain-SystemVerilog verification environment for an APB-to-SPI Master IP core.

The environment verifies:

- APB register access and reset values
- SPI modes 0, 1, 2, and 3
- 8-bit, 16-bit, and 32-bit transfers
- MSB-first and LSB-first shifting
- TX/RX FIFO behavior
- Interrupt status, masking, and W1C behavior
- Clock divider behavior
- Loopback mode
- Inter-transfer delay behavior
- Error/illegal-access scenarios
- CTRL.EN flush behavior

The testbench uses a lightweight SV-only architecture instead of UVM. It includes BFMs, a reference model, a scoreboard, functional coverage, and bound SystemVerilog assertions.

## Runtime Optimization

The individual tests are still implemented and can still be run one by one using:

```bash
make run TEST=<test_name> SEED=<seed>
````

However, `make regress` is optimized for runtime.

Instead of launching a new simulator process for every test, the regression runs a bundled test called:

```text
all_tests
```

`all_tests` internally calls all required test classes in one simulator session and resets the DUT/testbench state between tests.

This reduces repeated overhead from:

* multiple `vsim` startups
* repeated elaboration/loading
* repeated coverage database setup
* repeated UCDB saves per individual test

This keeps the full regression behavior while reducing total runtime.

## Directory Structure

```text
<submission_folder>/
  ├── assertions/
  │   └── spi_sva.sv
  ├── docs/
  │   ├── test_plan.pdf
  │   ├── final_report.pdf
  │   └── coverage_report.pdf
  ├── env/
  │   ├── coverage.sv
  │   └── ref_model.sv
  ├── sequences/
  │   └── stim_lib.sv
  ├── tb/
  │   ├── apb_master_bfm.sv
  │   ├── spi_slave_bfm.sv
  │   └── tb_top.sv
  ├── tests/
  │   ├── sanity_test.sv
  │   ├── reg_access_test.sv
  │   ├── mode_coverage_test.sv
  │   ├── width_coverage_test.sv
  │   ├── fifo_stress_test.sv
  │   ├── interrupt_test.sv
  │   ├── clk_div_corner_test.sv
  │   ├── loopback_test.sv
  │   ├── delay_transfer_test.sv
  │   ├── error_injection_test.sv
  │   ├── flush_test.sv
  │   ├── randomized_sanity_test.sv
  │   ├── ral_hw_reset_test.sv
  │   └── all_tests.sv
  ├── Makefile
  └── README.md
```

## Toolchain

Simulator:

```text
Siemens QuestaSim
```

The Makefile is configured for the Questa command-line flow using:

```text
vlib
vlog
vsim
vcover
```

Default simulator variable:

```make
SIMULATOR ?= questa
```

## How to Run

### Clean build artifacts

```bash
make clean
```

### Compile

```bash
make compile
```

### Run one individual test

Example:

```bash
make run TEST=fifo_stress_test SEED=1
```

Other examples:

```bash
make run TEST=sanity_test SEED=1
make run TEST=reg_access_test SEED=1
make run TEST=delay_transfer_test SEED=1
```

### Run the optimized full regression

```bash
make regress REGRESSION_SEEDS=1
```

By default, the Makefile uses:

```make
REGRESSION_SEEDS ?= 1
```

The regression runs `all_tests`, which calls all required tests in one simulator session.

### Generate coverage report

After running regression:

```bash
make cov
```

This produces:

```text
coverage_report.txt
```

## Regression Strategy

The individual tests remain available and are still the real verification units:

* `sanity_test`
* `reg_access_test`
* `mode_coverage_test`
* `width_coverage_test`
* `fifo_stress_test`
* `interrupt_test`
* `clk_div_corner_test`
* `loopback_test`
* `delay_transfer_test`
* `error_injection_test`
* `flush_test`
* `randomized_sanity_test`

For runtime, `make regress` dispatches:

```text
all_tests
```

`all_tests` calls the tests above in sequence and resets between them.

This preserves the behavior of the full regression while avoiding repeated simulator restarts.

## Verification Architecture

### Test Dispatcher

`tb_top.sv` reads the `+TESTNAME=<name>` plusarg and dispatches the selected test class.

Examples:

```text
+TESTNAME=sanity_test
+TESTNAME=delay_transfer_test
+TESTNAME=all_tests
```

### APB BFM

`apb_master_bfm.sv` provides blocking APB read/write tasks used by the tests.

### SPI Slave BFM

`spi_slave_bfm.sv` models the SPI slave side and adapts to:

* CPOL/CPHA mode
* transfer width
* bit ordering

### Reference Model / Scoreboard

`ref_model.sv` tracks expected DUT behavior and reports mismatches using:

```text
[SCOREBOARD_ERROR]
```

The model covers:

* register state
* FIFO state
* expected RX data
* interrupt expectations
* reset/flush behavior

### Functional Coverage

`coverage.sv` contains covergroups for:

* SPI mode
* transfer width
* bit order
* clock divider
* delay values
* FIFO occupancy
* interrupt behavior
* register access behavior

### Assertions

`spi_sva.sv` is bound into the DUT hierarchy and checks protocol/timing properties such as:

* IRQ aggregation
* APB zero-wait-state behavior
* MOSI stability around sample edges
* TX/RX overflow behavior
* RX empty read behavior
* SCLK timing
* transfer configuration stability

## Coverage Notes

The Makefile uses:

```make
COV_FLAG = +cover=sb
```

This enables statement and branch code coverage for speed.

Functional coverage is collected by the SystemVerilog covergroups in `coverage.sv`.

## Notes

* `make run TEST=<name>` remains available for debugging individual tests.
* `make regress` is optimized to run the full test set through `all_tests`.
* Wave dumping is off by default. Enable it only for debugging:

```bash
make run TEST=delay_transfer_test SEED=1 WAVES=1
```

* The Makefile keeps `+acc` disabled by default for speed.

```
```
