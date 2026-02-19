# Pre-UI Foundation Status

Stand: 2026-02-19

## Ziel dieses Dokuments

Abgrenzen, welche Kernbausteine vor der ersten echten Produkt-UI/UX technisch stehen müssen und welchen Status sie aktuell haben.

## Erledigt

- Rust Core Runtime als eigenständiger, testbarer Kern (`crates/syntic-core`).
- Dictation-Statusmaschine mit klaren Zustandsübergängen:
  - `idle -> listening -> reviewing -> confirmed`
  - `listening/reviewing -> cancelled`
  - `* -> failed`
- Fallback Command-Klassifikation (DE/EN Basis-Intent-Erkennung):
  - `set_timer`, `save_note`, `move_file`, `rename_file`, `unknown`
- Safety-Gate für Commands:
  - unknown wird abgelehnt
  - alle bekannten Intents erfordern explizite Bestätigung
  - destruktive Dateiaktionen sind explizit markiert
- FFI-API für macOS-Shell:
  - Runtime-Health JSON
  - Dictation State + Transition-Operationen
  - Command-Klassifikation + Safety JSON
- Swift-Bridge mit direkter Nutzung der neuen FFI-Endpunkte.
- macOS Adapter-Grundlage:
  - `MacOSTextInjectionAdapter` mit AX -> CGEvent -> Clipboard-Kette
  - `MacOSFinderContextAdapter` für Finder-Selektion via AppleScript
- STT-Routing-Regeln im Core (`local/cloud/auto`, Sensitive-Mode Override).
- Technischer E2E-Orchestrator in macOS-Shell:
  - `Option+Space` Trigger (Hotkey Adapter)
  - Audio-Capture über `AVAudioEngine`
  - STT-Routing über Core-Entscheidung
  - Review-State Übergang im Dictation-Core
  - Confirm -> TextInjection (AX -> CGEvent -> Clipboard-Fallback)
- Persistente App-Settings (Application Support / `settings.json`):
  - `locale`
  - `routingMode` (`auto/local/cloud`)
  - `sensitiveModeEnabled`
  - Schema-Version + Corrupt-Recovery mit Backup-Datei
- Persistenz für Session-Daten (History/Undo-Basis):
  - Session-History in `Application Support/Syntic/session-history.json`
  - Schema-Version + Corrupt-Recovery mit Backup-Datei
  - Undo-Basis: letzter bestätigter Transcript kann in Review-Zustand zurückgeführt werden
- Session-History im Core/FFI gespiegelt:
  - In-Memory Session-History-Journal im Core (record/since/clear/undo-mark)
  - FFI-Endpunkte für Session-History-Record/Undo/Feed/Clear
  - macOS-Pipeline spiegelt Persist-/Undo-Operationen zusätzlich in den Core
- Core-Event-Routing (Error + Permission):
  - In-memory Event-Journal im Core (Ring-Buffer)
  - FFI-Endpunkte für Event-Report und Event-Feed
  - macOS-Pipeline meldet Permission-/Fehlerzustände an Core-Events
- E2E-Telemetrie als strukturierte Events/Logs:
  - Core-Telemetry-Events (`category/action/status/context/value_ms`)
  - NDJSON-Log unter `Application Support/Syntic/logs/e2e-telemetry.ndjson`
- Core-Feed-Projektion als Persistenzgrundlage:
  - inkrementeller Konsum von `core_events`, `domain_events`, `tool_runtime_signals`, `session_history`
  - NDJSON-Projektion unter `Application Support/Syntic/logs/core-feed-projection.ndjson`
- Domain-Event-Ketten bis Tool Runtime:
  - `review_cancel` -> Abort-Queue/Task-Cancellation
  - `review_confirm` -> Commit/Execution-Start der Pending Tool-Invocations
  - strukturierte Runtime-Resultate inkl. `rejectionCode`
- Signing/Notarization-Grundlage für macOS:
  - Packaging-Profil (`Info.plist` + Entitlements)
  - Lokaler Packaging-Runner ohne Developer-ID (`scripts/release/macos-package-local-app.sh`)
  - Release-Runner (`scripts/release/macos-package-sign-notarize.sh`)
  - Erweiterter Spike-04 Preflight mit Fail-fast Checks
  - Release-Runner startet Preflight verpflichtend vor Build/Sign/Notarize
  - CI-Workflow-Basis für signierten Build (+ optionale Notarization) vorhanden
- Build- und Testkette (Rust + macOS Swift Build) grün.

## Noch vor erster Produkt-UI nötig

- Entitlements/Signing operativ schließen:
  - Team-/Issuer-Credentials und CI-Secrets bereitstellen
  - ersten erfolgreichen Notarization-Run dokumentieren

## Bewusst noch nicht begonnen

- Produkt-UI/UX-Design (Onboarding, final Settings Layout, finale Palette-Interaktion).
- Visuelles Design-System und Interaction-Polish.

## Nächster technischer Fokus

1. Entitlements/Signing operativ abschließen (Credentials + erster grüner Notarization-Lauf).
2. Event-Feed konsumierend in Produkt-UI statt Debug-Textprojektion.
3. Release- und Notarization-Flow in CI mit echten Secrets und erstem grünen Workflow-Lauf operationalisieren.
