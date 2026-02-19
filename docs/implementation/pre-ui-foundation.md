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
- Build- und Testkette (Rust + macOS Swift Build) grün.

## Noch vor erster Produkt-UI nötig

- Fehler-/Permission-Routing in Core-Events statt rein lokalem Debug-Status.
- E2E-Technikfluss erweitern:
  - Review Cancel/Fail in Domain-Events ausleitbar machen
- Entitlements/Signing-Blocker aus Spike 4 auflösen.

## Bewusst noch nicht begonnen

- Produkt-UI/UX-Design (Onboarding, final Settings Layout, finale Palette-Interaktion).
- Visuelles Design-System und Interaction-Polish.

## Nächster technischer Fokus

1. Fehler-/Permission-Routing als Core-Events modellieren.
2. Entitlements/Signing-Blocker aus Spike 4 auflösen.
3. E2E-Telemetrie aus Debug-UI in strukturierte Logs/Events überführen.
4. Persistenz für Session-Daten (History/Undo) mit Migrationspfad einführen.
