# macOS Signing + Notarization Runbook

Stand: 2026-02-19

## Ziel

Reproduzierbarer Developer-ID Build mit Hardened Runtime, Verifikation und optionaler Notarization.

## Vorbedingungen

- Vollständiges Xcode aktiv (`xcode-select -p` zeigt auf `/Applications/Xcode.app/...`)
- Mindestens eine `Developer ID Application` Identity im Keychain
- `notarytool` verfügbar (`xcrun --find notarytool`)
- Notarization-Auth konfiguriert:
  - entweder `NOTARYTOOL_PROFILE` (Keychain-Profil),
  - oder API-Key-Daten (`NOTARY_AUTH_MODE=api_key`, `NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID`, `NOTARY_ISSUER_ID`)

## Preflight

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-04-notarization-preflight.sh
```

Der Runner beendet mit Exit-Code `1`, wenn ein kritischer Check fehlschlägt.
Für CI/Release-Gates kann `REQUIRE_NOTARY_AUTH=1` gesetzt werden.

## Build + Sign + Notarize

```bash
cd /Users/carstenrheidt/Syntic
export CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export NOTARYTOOL_PROFILE="syntic-notary"
./scripts/release/macos-package-sign-notarize.sh
```

Alternative mit App-Store-Connect API-Key:

```bash
cd /Users/carstenrheidt/Syntic
export CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export NOTARY_AUTH_MODE="api_key"
export NOTARY_API_KEY_PATH="/abs/path/AuthKey_ABC123DEFG.p8"
export NOTARY_API_KEY_ID="ABC123DEFG"
export NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000"
./scripts/release/macos-package-sign-notarize.sh
```

Der Release-Runner führt den Spike-04-Preflight automatisch als ersten Schritt aus
und bricht bei fehlenden Signing-/Notary-Voraussetzungen sofort ab.

## Lokaler Dry-Run ohne Notarization

```bash
cd /Users/carstenrheidt/Syntic
export CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export SKIP_NOTARIZATION=1
./scripts/release/macos-package-sign-notarize.sh
```

Artefakte landen unter `dist/macos/`.

## Packaging-Artefakte

- Info.plist-Template: `apps/macos/Packaging/Info.plist`
- Entitlements-Profil: `apps/macos/Packaging/SynticRelease.entitlements`

## Entscheidungsregel für Entitlements

- Baseline ist ein minimales Profil ohne zusätzliche Hardened-Runtime-Ausnahmen.
- Jede neue Entitlement muss auf einen reproduzierbaren Notarization-/Runtime-Fehler zurückführbar sein.
- Entitlement-Erweiterungen sind im Commit und im Spike-Dokument zu begründen.
