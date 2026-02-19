# Spike 04 — Notarization + Entitlements (macOS)

Status: Systematisiert (Tooling + Packaging-Artefakte umgesetzt)  
Datum: 2026-02-19  
Owner: Syntic Core Team

## Ziel

Früh validieren, ob unsere geplanten Capabilities und Distribution-Form den Apple-Notarization-Flow ohne Blocker durchlaufen.

## Leitfragen

- Welche Entitlements sind für MVP minimal notwendig?
- Ist Signing/Notarization-Tooling auf der Build-Maschine vollständig?
- Gibt es früh erkennbare Policy-Risiken (Input Monitoring + AX + Apple Events)?

## Scope dieses Spikes

- Tooling-Preflight (Xcode, codesign, notarytool, sign identities)
- Entitlement-Liste festlegen (Draft)
- Notarization-Probe auf minimalem App-Bundle vorbereiten

## MVP Entitlements (aktualisiert)

- `apps/macos/Packaging/SynticRelease.entitlements` ist als Minimalprofil angelegt.
- Baseline: keine zusätzlichen Hardened-Runtime-Ausnahmen.
- Erweiterungen werden nur bei reproduzierbarem Signing/Runtime-Fehler ergänzt.

## Preflight-Runner

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-04-notarization-preflight.sh
```

## Release-Runner

```bash
cd /Users/carstenrheidt/Syntic
export CODESIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
export NOTARYTOOL_PROFILE="syntic-notary"
./scripts/release/macos-package-sign-notarize.sh
```

## Ergebnis-Checklist

| Check | Erwartung | Status | Details |
|---|---|---|---|
| Xcode selected | `/Applications/Xcode.app/...` | Automatisiert | Preflight-Check vorhanden |
| codesign available | vorhanden | Automatisiert | Preflight-Check vorhanden |
| notarytool available | vorhanden | Automatisiert | Preflight-Check vorhanden |
| codesign identities | >=1 Developer ID | Automatisiert | Preflight-Check vorhanden |
| security unlock state | nutzbar im Build | Offen | abhängig von lokaler Maschine/CI-Keychain |
| Packaging Info.plist | vorhanden inkl. Usage-Keys | Erledigt | `apps/macos/Packaging/Info.plist` |
| Entitlements-Profil | minimal + versioniert | Erledigt | `apps/macos/Packaging/SynticRelease.entitlements` |
| Sign/Notarize Runner | reproduzierbar | Erledigt | `scripts/release/macos-package-sign-notarize.sh` |

## Entscheidungsregeln

- Wenn `notarytool` oder Developer-ID fehlt: Notarization-Spike blockiert, zuerst Tooling fixen.
- Wenn Entitlements reduziert werden müssen: Feature-Degradation explizit dokumentieren.
- Wenn Notarization-Probe failt: Fehlerursache nach Kategorie mappen (Signing, Entitlements, Packaging, Policy).

## Offene Punkte

- Wer stellt die finalen Team-/Issuer-Credentials für notarytool bereit?
- Wird Sparkle-Signierung parallel oder nach Notarization-Spike eingeführt?
- CI-Secrets für Signing/Notarization anlegen (Developer-ID + Notarytool Profilzugriff).

## Letzter lokaler Preflight

Datum: 2026-02-19  
Command: `./scripts/spikes/spike-04-notarization-preflight.sh`

- Pass: Xcode selected, codesign/xcodebuild/xcrun/security, notarytool, Packaging-Profile
- Fail: `codesign-identities` (`no Developer ID Application identity found`)
