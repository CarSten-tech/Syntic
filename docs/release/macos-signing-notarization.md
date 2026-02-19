# macOS Signing + Notarization Runbook

Stand: 2026-02-19

## Ziel

Reproduzierbarer Developer-ID Build mit Hardened Runtime, Verifikation und optionaler Notarization.

## Vorbedingungen

- Vollständiges Xcode aktiv (`xcode-select -p` zeigt auf `/Applications/Xcode.app/...`)
- Mindestens eine `Developer ID Application` Identity im Keychain
- `notarytool` verfügbar (`xcrun --find notarytool`)
- `NOTARYTOOL_PROFILE` im Keychain konfiguriert (für echten Notarization-Lauf)

## Preflight

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-04-notarization-preflight.sh
```

Der Runner beendet mit Exit-Code `1`, wenn ein kritischer Check fehlschlägt.

## Build + Sign + Notarize

```bash
cd /Users/carstenrheidt/Syntic
export CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export NOTARYTOOL_PROFILE="syntic-notary"
./scripts/release/macos-package-sign-notarize.sh
```

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
