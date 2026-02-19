#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-debug}"

if [[ "${PROFILE}" == "release" ]]; then
  cargo build --manifest-path "${ROOT_DIR}/Cargo.toml" -p syntic-ffi --release
  LIB_PATH="${ROOT_DIR}/target/release/libsyntic_ffi.a"
else
  cargo build --manifest-path "${ROOT_DIR}/Cargo.toml" -p syntic-ffi
  LIB_PATH="${ROOT_DIR}/target/debug/libsyntic_ffi.a"
fi

if [[ ! -f "${LIB_PATH}" ]]; then
  echo "error: expected Rust static library missing at ${LIB_PATH}" >&2
  exit 1
fi

echo "Rust FFI static library ready: ${LIB_PATH}"
