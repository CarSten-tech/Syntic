# Syntic

Syntic ist eine macOS-first Voice-Produktivitäts-App mit Rust-Core und nativer SwiftUI-Shell.

## Bootstrap-Stand

Dieses Repository enthält den initialen Projekt-Scaffold:

- Rust Workspace (`crates/syntic-core`, `crates/syntic-ffi`)
- C-ABI Header für FFI (`crates/syntic-ffi/include/syntic_ffi.h`)
- macOS SwiftUI Menu-Bar Shell (`apps/macos`)
- CI-Grundpipeline (Rust + Swift Build/Lint)

## Voraussetzungen

- Rust toolchain (stable)
- Xcode Command Line Tools (für `swift build`)

## Lokale Commands

```bash
# Rust: format, lint, test
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-targets --all-features

# Rust static library for Swift FFI
./scripts/build-ffi.sh

# Swift shell bauen
swift build --package-path apps/macos

# Spike 2 Finder-Selection Snapshot
./scripts/spikes/spike-02-finder-selection.sh --label "Case 1"

# Spike 3 STT-Messzeile loggen
./scripts/spikes/spike-03-log-measurement.sh --provider sfspeech --seconds 2 --locale de-DE --noise quiet --first-latency-ms 180 --final-latency-ms 430 --quality 4

# Spike 4 Notarization Preflight
./scripts/spikes/spike-04-notarization-preflight.sh
```

## Nächste Schritte

1. FFI im Release-Profil testen: `./scripts/build-ffi.sh release`.
2. Erste End-to-End Verbindung: SwiftUI Menu-Bar -> Rust FFI-Call -> UI-Ausgabe.
3. Spikes 1-4 aus `docs/architecture/voice-app-plan.md` durchführen.
