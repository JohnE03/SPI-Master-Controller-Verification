SPI Master Verification Environment (SV-Only)
Overview
This repository contains a complete, plain-SystemVerilog verification environment for an APB-to-SPI Master IP core. The testbench rigorously verifies the DUT's register map, FIFO queues, interrupt handling, protocol states, and timing dividers.

The environment achieves 86.68% Functional Coverage across all configurations and features 0 Assertion Failures under heavy constrained-random stress testing.

Directory Structure
Plaintext
<submission_folder>/
  ├── assertions/
  │   └── spi_sva.sv               # SystemVerilog Assertions (IRQ, Timing, Protocol)
  ├── docs/
  │   ├── test_plan.pdf            # Written test plan and strategies
  │   ├── final_report.pdf         # Final project architecture report
  │   └── coverage_report.pdf      # Exported QuestaSim coverage report (86.68%)
  ├── env/
  │   ├── coverage.sv              # Functional covergroups (Config, IRQ, FIFOs, Timing)
  │   └── ref_model.sv             # Plain-SV Scoreboard and Predictor
  ├── sequences/
  │   └── stim_lib.sv              # Constrained-random spi_txn classes
  ├── tb/
  │   ├── apb_master_bfm.sv        # APB bus functional model (tasks: apb_write/read)
  │   ├── spi_slave_bfm.sv         # SPI slave responder (handles CPOL/CPHA, multi-width)
  │   └── tb_top.sv                # Testbench Top (Instantiates DUT, BFMs, SVA, and dispatches tests)
  ├── tests/
  │   ├── sanity_test.sv           # Directed loopback check
  │   ├── randomized_sanity_test.sv# Constrained-random config testing
  │   ├── reg_access_test.sv       # APB Register map default and R/W testing
  │   ├── mode_coverage_test.sv    # SPI Modes 0-3 sweep
  │   ├── width_coverage_test.sv   # 8-bit, 16-bit, and 32-bit transfer sweep
  │   ├── fifo_stress_test.sv      # TX/RX FIFO full/empty flag validation
  │   ├── interrupt_test.sv        # Sticky bits, W1C traps, and race condition attacks
  │   ├── clk_div_corner_test.sv   # Max divider (65535) and mid-transfer hold checks
  │   ├── loopback_test.sv         # Internal shift register routing check
  │   ├── delay_transfer_test.sv   # Inter-transfer idle gap timing check
  │   ├── error_injection_test.sv  # TX/RX Overflow, Underflow, and Reserved Address hits
  │   └── flush_test.sv            # Mid-transfer abort and queue clearing (CTRL.EN = 0)
  ├── Makefile                     # Simulation and regression execution script
  └── README.md                    # This file
How to Run (Execution)
This project uses a standard Makefile built for Siemens QuestaSim.

Run a single test (e.g., fifo_stress_test):

Bash
make run TEST=fifo_stress_test SEED=1234
Run the full Regression Suite (12 Tests × 20 Seeds):

Bash
make regress
Note: The regression script ensures all tests complete within the 10,000 maximum invocations limit, and tb_top.sv contains a 10ms hardware timeout fail-safe to prevent infinite loops.

Generate the Coverage Report:

Bash
make cov
(This extracts the merged.ucdb database into a readable text format).

Verification Architecture
Because this is an SV-only testbench, UVM is bypassed in favor of a lightweight, highly effective object-oriented structure:

Test Dispatcher: tb_top.sv receives the +TESTNAME argument and executes the corresponding static run() task inside the target test class.

Scoreboard (ref_model.sv): A custom software reference model that mirrors the DUT's 9 APB registers, models the 8-deep TX/RX FIFOs, predicts SPI transfer times mathematically, and calculates expected interrupt states.

Stimulus (stim_lib.sv): Uses SystemVerilog rand variables and inline with {} constraints to randomize Clock Dividers, SPI Modes, Shift Directions, Transfer Widths, and Delays.

BFMs (apb_master_bfm.sv / spi_slave_bfm.sv): The APB master handles blocking reads/writes, while the SPI slave dynamically adapts to randomized CPOL/CPHA settings and multi-bit transfer widths to stream data back to the scoreboard.

SystemVerilog Assertions (spi_sva.sv): Bound directly to the DUT instances. Assertions strictly monitor:

APB PREADY zero-wait-state constraints.

Real-time IRQ generation mapped to INT_STAT and INT_EN.

SPI SCLK frequency rules.

Configuration hold states (ensuring parameters do not shift mid-transfer).

Coverage Highlights
The testbench utilizes 4 primary Covergroups (cg_config, cg_interrupts, cg_fifo_occupancy, cg_timing).
Through 200+ randomized regression seeds, the environment successfully explores edge cases including extreme Clock Dividers paired with high Delays, ensuring thorough mathematical verification of the SPI Master's FSM.