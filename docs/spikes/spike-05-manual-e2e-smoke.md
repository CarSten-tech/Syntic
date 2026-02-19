# Spike 05 — Manueller macOS E2E Smoke Run

Status: Ausfuehrbar  
Datum: 2026-02-19  
Owner: Syntic Core Team

## Ziel

Reproduzierbare technische End-to-End-Pruefung fuer:

- Hotkey/Trigger -> Audio -> Apple Speech STT -> Review
- Review Confirm -> Injection (direkt)
- Review Confirm -> Injection (Clipboard-Fallback)
- STT Permission-Fehler -> strukturierte Core-Events/Telemetry

## Vorbedingungen

- App lokal gebaut (`swift build --package-path apps/macos`)
- Menu-Bar-App laeuft (`swift run --package-path apps/macos`)
- Logs vorhanden:
  - `~/Library/Application Support/Syntic/logs/e2e-telemetry.ndjson`
  - `~/Library/Application Support/Syntic/logs/core-feed-projection.ndjson`

## Hilfsskript

`scripts/spikes/spike-05-e2e-smoke-check.sh`

Kommandos:

- Zeitmarke setzen:
  - `MARK_MS="$(./scripts/spikes/spike-05-e2e-smoke-check.sh mark)"`
- Szenario validieren:
  - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario direct_injection`
  - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario clipboard_fallback`
  - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario stt_permission_denied`

## Szenario A: Direct Injection

1. Zeitmarke setzen:
   - `MARK_MS="$(./scripts/spikes/spike-05-e2e-smoke-check.sh mark)"`
2. In einem normalen Textfeld diktieren:
   - Trigger starten
   - sprechen
   - Trigger stoppen
   - Review bestaetigen
3. Validieren:
   - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario direct_injection`

Erwartung:

- `ok|smoke_check|scenario=direct_injection`
- Telemetry enthaelt `stt.transcription_completed`
- Injection-Event hat `disposition=injected` und `status=ok`

## Szenario B: Clipboard Fallback

1. App mit erzwungenem Clipboard-Fallback starten:
   - `SYNTIC_FORCE_CLIPBOARD_FALLBACK=1 swift run --package-path apps/macos`
2. Zeitmarke setzen:
   - `MARK_MS="$(./scripts/spikes/spike-05-e2e-smoke-check.sh mark)"`
3. Diktat einmal komplett durchlaufen und Review bestaetigen.
4. Validieren:
   - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario clipboard_fallback`

Erwartung:

- `ok|smoke_check|scenario=clipboard_fallback`
- Injection-Event hat `disposition=clipboard_fallback` und `status=fallback`

## Szenario C: STT Permission Denied

1. Speech Recognition fuer Syntic in macOS Datenschutz-Einstellungen entziehen.
2. Zeitmarke setzen:
   - `MARK_MS="$(./scripts/spikes/spike-05-e2e-smoke-check.sh mark)"`
3. Diktat-Flow starten und stoppen (bis STT-Fehler eintritt).
4. Validieren:
   - `./scripts/spikes/spike-05-e2e-smoke-check.sh verify --since-ms "${MARK_MS}" --scenario stt_permission_denied`

Erwartung:

- `ok|smoke_check|scenario=stt_permission_denied`
- Core-Event `permission=speech_recognition` `status=denied`
- Core-Error-Code `speech_permission_denied`
- Telemetry `stt.transcription_failed` mit `error_code=speech_permission_denied`

## Hinweise

- Das Skript validiert nur neue Events seit `--since-ms`.
- Wenn keine neuen Events erscheinen, zuerst pruefen ob die App noch laeuft und ob der Trigger wirklich einen Durchlauf ausgeloest hat.
