#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Martin Havlik <omnitex.git@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# Clone the DIP fork of idf-extra-components and build the desired app.
# Requires ESP-IDF to be sourced (. $HOME/esp/v5.../export.sh or similar).

set -euo pipefail

FORK_URL="https://github.com/omnitex/idf-extra-components.git"
FORK_BRANCH="DIP"
CLONE_DIR="idf-extra-components"

# ---------- helpers ----------

step()  { printf "\n===> %s\n" "$1"; }
die()   { printf "ERROR: %s\n" "$1" >&2; exit 1; }

check_idf() {
    if [ -z "${IDF_PATH:-}" ]; then
        die "ESP-IDF not found. Source export.sh first:
  . \$HOME/esp/v5.*/esp-idf/export.sh"
    fi
    step "ESP-IDF: $IDF_PATH"
}

# ---------- clone ----------

clone_fork() {
    if [ -d "$CLONE_DIR" ]; then
        step "Reusing existing clone ($CLONE_DIR)"
    else
        step "Cloning fork ($FORK_BRANCH branch)..."
        git clone --depth 1 --branch "$FORK_BRANCH" "$FORK_URL" "$CLONE_DIR"
    fi
}

# ---------- build ----------

build_ftl_eval() {
    step "Building ftl_eval..."
    (
        cd "$CLONE_DIR/spi_nand_flash/ftl_eval"
        idf.py --preview set-target linux
        idf.py build
    )
}

build_host_test() {
    local sdkconfig_extra="${1:-}"
    if [ -n "$sdkconfig_extra" ]; then
        step "Building host_test (sdkconfig.defaults + $sdkconfig_extra)..."
        (
            cd "$CLONE_DIR/spi_nand_flash/host_test"
            SDKCONFIG_DEFAULTS="sdkconfig.defaults;$sdkconfig_extra" idf.py --preview set-target linux
            idf.py build
        )
    else
        step "Building host_test (default config)..."
        (
            cd "$CLONE_DIR/spi_nand_flash/host_test"
            idf.py --preview set-target linux
            idf.py build
        )
    fi
}

build_perf_app() {
    step "Building perf_app..."
    (
        cd "$CLONE_DIR/spi_nand_flash/perf_app"
        idf.py set-target esp32s3
        idf.py build
    )
}

# ---------- main ----------

main() {
    check_idf
    clone_fork

    step "Choose what to build:"
    echo "  1) ftl_eval       — FTL parameter sweep app (Linux)"
    echo "  2) host_test      — unit tests, baseline config"
    echo "  3) host_test      — BDL + orphan replay tests (sdkconfig.bdl)"
    echo "  4) host_test      — BDL + all caches + page relief (sdkconfig.bdl.caches)"
    echo "  5) perf_app       — performance benchmarks (needs ESP32-S3 hardware)"
    echo "  6) skip build"
    read -r -p "> " choice

    case "$choice" in
        1) build_ftl_eval ;;
        2) build_host_test ;;
        3) build_host_test "sdkconfig.bdl" ;;
        4) build_host_test "sdkconfig.bdl.caches" ;;
        5) build_perf_app ;;
        6) ;;
        *) die "Invalid choice" ;;
    esac

    echo ""
    step "Done"
    echo "  Fork:      $CLONE_DIR/"
    echo "  ftl_eval:  $CLONE_DIR/spi_nand_flash/ftl_eval/"
    echo "  host_test: $CLONE_DIR/spi_nand_flash/host_test/"
    echo "  perf_app:  $CLONE_DIR/spi_nand_flash/perf_app/"
    echo ""
    echo "Run FTL evaluations:"
    echo "  cd $CLONE_DIR/spi_nand_flash/ftl_eval"
    echo "  make run CONFIG=zipf_skew_1.0"
    echo "  make runall"
    echo ""
    echo "Run host tests:"
    echo "  cd $CLONE_DIR/spi_nand_flash/host_test"
    echo "  ./build/nand_flash_host_test.elf            # all tests"
    echo "  ./build/nand_flash_host_test.elf \"[dhara_oob][replay]\"  # orphan replay only"
}

main "$@"
