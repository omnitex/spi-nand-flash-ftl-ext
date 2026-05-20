# SPI NAND Flash FTL Extensions

Extensions to the [Espressif `spi_nand_flash`](https://github.com/espressif/idf-extra-components/tree/master/spi_nand_flash) component for ESP-IDF, focused on FTL evaluation, fault simulation, and wear-leveling improvements built on top of the [Dhara](https://github.com/dlbeer/dhara) FTL library.

> **Source code** lives in a fork of `idf-extra-components`:
> [`github.com/omnitex/idf-extra-components`](https://github.com/omnitex/idf-extra-components) on the `DIP` branch.
> This repo contains documentation, evaluation results, and a build setup.

## What's New

The `DIP` branch extends the upstream `spi_nand_flash` component with:

### Improved power-loss recovery via orphan page replay 
By storing Logical Page Number (LPN) of each page in its out-of-band (OOB) area, mapping layer information is now durable with each page write, compared to previously only on page group sized checkpoint intervals.

### NAND Fault Simulator
A configurable fault-injection layer (`nand_fault_sim`) that replaces the Linux mmap emulation at link time.

### Page-Register Cache
Tracks which page is currently loaded in the NAND chip's internal data register. Skips redundant `READ PAGE` commands (~25-100 us) on back-to-back reads of the same page. Reset automatically after every program or erase. Toggle via `CONFIG_NAND_PAGE_REGISTER_CACHE`.

### Metadata Cache
DRAM-resident cache for Dhara metadata pages (`CONFIG_DHARA_META_CACHE_SLOTS`, 0-8 slots). Avoids re-reading metadata that the wear-leveling layer accesses repeatedly.

### Map-Path Cache
Caches the Dhara radix-tree traversal path for sequential sector lookups (`CONFIG_DHARA_MAP_PATH_CACHE`). Eliminates most per-sector metadata reads during sequential workloads. 136 bytes static RAM.

### Program Page Relief
Before programming a page, reads it back to check ECC condition. If correctable-bit count is above a configurable threshold, the page is skipped and the next available page is used -- preventing writes to already-worn pages. Three aggressiveness levels via Kconfig.

### FTL Evaluation App (`ftl_eval`)
Host-test application for automated parameter sweeps:
- Configurable workloads: sequential, random, mixed, Zipf-distributed
- Sweep parameters: GC factor, write sizes, ECC noise, page relief thresholds
- JSON output with metrics (WAF, lifetime, erase distribution)
- Built-in visualization (`ftl_viz.py`) for heatmaps and comparison plots
- Fault-simulation integration for robustness testing

### Performance Benchmark App (`perf_app`)
Host-test application measuring raw throughput and latency:
- Sequential/random/Zipf benchmarks
- Metadata cache hit-rate statistics
- Automated run scripts and result inventory (`perf_inventory.py`, `perf_viz.py`)

### Extended Host Tests
- BDL (Block Device Layer) test suite
- Fault-injection test suite (fault simulation + FTL robustness)
- Page relief unit tests

## Architecture

```
Application / FS
       |
  spi_nand_flash API   (backward compatible)
       |
  Dhara FTL            (wear leveling + garbage collection)
   |         |
  L3 path   L2 meta cache
  cache     (DRAM slots)
   |
  NAND Wear-Leveling BDL
       |
  NAND Flash BDL
       |
  +------------ or ------------+
  |                            |
  SPI NAND Operations      NAND Emulation
  (ESP chips)              (Linux host test)
                                |
                          +-----+------+
                          |            |
                    mmap emul     fault sim
                    (baseline)    (inject faults)
```

## Quick Start

### Prerequisites

- ESP-IDF v6.x ([installation guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/))

### Clone and Build

```bash
# 1. Clone this repo
git clone https://github.com/omnitex/spi-nand-flash-ftl-ext.git
cd spi-nand-flash-ftl-ext

# 2. Run setup (clones the fork, builds ftl_eval and perf_app)
./setup.sh
```

```
# Or build manually:
git clone -b DIP https://github.com/omnitex/idf-extra-components.git
cd idf-extra-components/spi_nand_flash/ftl_eval
idf.py --preview set-target linux
idf.py build
```

### Run FTL Evaluations

```bash
cd idf-extra-components/spi_nand_flash/ftl_eval

# Run a single sweep config
make run CONFIG=gc_vs_wear_sequential_monotonic

# Visualize results
python3 ftl_viz.py --no-tex
```

### Run Host Tests

The `host_test/` directory contains Catch2-based test suites that exercise the NAND driver and FTL on the Linux target (no hardware needed). Which tests are compiled depends on Kconfig options.

#### Legacy FTL tests (no BDL)

Tests for the standard FTL API: write/read/copy/trim/sync, GC stability, sequential sweeps, edge cases. Runs with the mmap NAND emulator.

```bash
cd idf-extra-components/spi_nand_flash/host_test

# Default build (baseline, stats enabled)
idf.py --preview set-target linux
idf.py build monitor
```

Available test tags: `[spi_nand_flash]`, `[ftl]`, `[ftl][gc]`, `[ftl][rw]`, `[ftl][sequential]`, `[ftl][copy]`, `[ftl][trim]`, `[ftl][sync]`, `[ftl][bounds]`, `[ftl][patterns]`.

#### BDL tests + OOB LPN orphan replay (requires ESP-IDF 6.0+)

When `CONFIG_NAND_FLASH_ENABLE_BDL=y`, an extended test suite is compiled including the **OOB LPN orphan replay** tests. These verify that pages written after the last Dhara checkpoint (orphan pages) are correctly recovered on remount by replaying their OOB-stored logical page numbers — the core crash-recovery mechanism.

Two overlay configs are provided. Apply one with `SDKCONFIG_DEFAULTS`:

```bash
cd idf-extra-components/spi_nand_flash/host_test

# BDL only (bare — orphan replay tests, raw BDL tests, WL BDL tests)
SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.bdl" idf.py --preview set-target linux
idf.py build monitor

# BDL + all read-path optimizations (L1/L2/L3 caches + page relief)
SDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.bdl.caches" idf.py --preview set-target linux
idf.py build monitor
```

Available BDL test tags: `[bdl]`, `[bdl][raw]`, `[bdl][wl]`, `[bdl][raw][sequential]`, `[bdl][raw][stress]`, `[bdl][raw][copy]`.

Orphan replay tests: `[dhara_oob]`, `[dhara_oob][replay]`, `[dhara_oob][replay][boundary]`.

```bash
# Run only orphan replay tests (crash-recovery feature)
./build/nand_flash_host_test.elf "[dhara_oob][replay]"
```

#### Optimization configs at a glance

| Config file | What's enabled |
|-------------|----------------|
| *(defaults only)* | Linux target, stats — baseline |
| `sdkconfig.bdl` | + BDL, orphan replay tests |
| `sdkconfig.bdl.caches` | + BDL, L1/L2/L3 caches, page relief |

Individual options can also be toggled via `idf.py menuconfig` under *Component config → SPI NAND Flash configuration*. Cache statistics (`spi_nand_cache_stats_t`) and relief statistics (`spi_nand_relief_stats_t`) are printed at the end of each test run when `CONFIG_NAND_ENABLE_STATS=y`.

## Kconfig Options (Linux Target)

| Option | Description |
|--------|-------------|
| `CONFIG_NAND_PAGE_REGISTER_CACHE` | L1 page-register cache |
| `CONFIG_DHARA_META_CACHE_SLOTS` | L2 metadata cache (0-8 DRAM slots) |
| `CONFIG_DHARA_MAP_PATH_CACHE` | L3 map-path cache (136 bytes) |
| `CONFIG_NAND_ENABLE_STATS` | Runtime statistics collection |
| `CONFIG_NAND_FLASH_PROG_PAGE_RELIEF` | Program page relief |
| `CONFIG_NAND_FLASH_FAULT_SIM` | Fault-injection simulator |

## Directory Layout

```
spi-nand-flash-ftl-ext/
  setup.sh              Clone fork and build apps
  docs/                 Deep architecture and design docs
  results/              Evaluation outputs (plots, data)
```

The actual source code is in the [`idf-extra-components` fork](https://github.com/omnitex/idf-extra-components/tree/DIP/spi_nand_flash):

```
spi_nand_flash/
  include/              Public API headers
  priv_include/         Internal headers
  src/                  Driver implementation
    nand_fault_sim.c    Fault-injection simulator
    dhara_glue.c        Dhara FTL integration (caches, relief)
    nand_impl.c         NAND operations + L1 cache
  ftl_eval/             FTL evaluation app + configs + viz
  perf_app/             Performance benchmark app + viz
  host_test/            Extended test suites
  Kconfig               All configuration options
```

## License

This repository is licensed under [Apache-2.0](LICENSE).  
The `spi_nand_flash` component in the fork incorporates the [Dhara library](https://github.com/dlbeer/dhara), licensed under its own [MIT-style license](https://github.com/dlbeer/dhara/blob/master/LICENSE).
