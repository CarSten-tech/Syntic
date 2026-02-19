# Spike 02 — Finder Selection Zuverlässigkeit (macOS)

Status: In Arbeit  
Datum: 2026-02-19  
Owner: Syntic Core Team

## Ziel

Beantworten, unter welchen Bedingungen Finder-Selektion via AppleScript zuverlässig gelesen werden kann und wann sie leer oder fehlerhaft zurückkommt.

## Leitfrage

Wann gibt AppleScript eine leere Liste zurück, obwohl Dateien selektiert sind?

## Testumgebung

- macOS Ventura 13.7.x
- Finder geöffnet
- Syntic Repo mit Skript: `scripts/spikes/spike-02-finder-selection.sh`

## Testfälle (aus Architekturplan)

1. Finder im Vordergrund, ein Fenster, List View
2. Finder im Hintergrund, anderes App-Fenster aktiv
3. Mehrere Finder-Fenster offen
4. Finder nicht sichtbar/kein Finder-Fenster
5. Selektion in Column View
6. Selektion in List View
7. Selektion in Gallery View

## Ergebnis-Matrix

| Timestamp | Label | Finder running | Finder frontmost | Window count | View | Selected count | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| TBD | Case 1 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 2 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 3 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 4 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 5 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 6 | TBD | TBD | TBD | TBD | TBD | TBD | |
| TBD | Case 7 | TBD | TBD | TBD | TBD | TBD | TBD | |

## Durchführung

Beispielaufruf:

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-02-finder-selection.sh --label "Case 1" --append docs/spikes/spike-02-finder-selection-reliability.md
```

Das Skript:

- liest Finder-Zustand (running/frontmost/window count/view)
- liest selektierte Pfade aus Finder
- bewertet den Status (`ok`, `empty-selection`, `finder-not-running`, `error`)
- gibt eine Markdown-Zeile aus
- hängt optional die Zeile in den Run-Log unten an

## Entscheidungsregeln

- `ok` in allen Kernfällen: AppleScript-Ansatz bleibt primär.
- `empty-selection` in legitimen Selektionsfällen: App muss klaren "kein Kontext"-Fallback + Retry anbieten.
- wiederkehrende Inkonsistenz bei Multi-Window/Background: AX-basierte Finder-Context-Alternative evaluieren.

## Offene Punkte

- Soll bei `empty-selection` automatisch ein zweiter Read nach kurzer Verzögerung erfolgen?
- Brauchen wir app-spezifisches Debouncing vor File-Intent-Ausführung?

## Run-Log (append-only)

| Timestamp | Label | Finder running | Finder frontmost | Window count | View | Selected count | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-02-19 13:40:57 | Baseline: Finder frontmost, no selection | true | false | 1 | list view | 0 | empty-selection |  |
