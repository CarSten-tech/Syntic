# Spike 04 — Notarization + Entitlements (macOS)

Status: Vorbereitet  
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

## MVP Entitlements (Draft)

- `com.apple.security.device.audio-input`
- `com.apple.security.temporary-exception.apple-events`
- optional nur falls nötig: `com.apple.security.cs.allow-jit`

## Preflight-Runner

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-04-notarization-preflight.sh
```

## Ergebnis-Checklist

| Check | Erwartung | Status | Details |
|---|---|---|---|
| Xcode selected | `/Applications/Xcode.app/...` | TBD | |
| codesign available | vorhanden | TBD | |
| notarytool available | vorhanden | TBD | |
| codesign identities | >=1 Developer ID | TBD | |
| security unlock state | nutzbar im Build | TBD | |

## Entscheidungsregeln

- Wenn `notarytool` oder Developer-ID fehlt: Notarization-Spike blockiert, zuerst Tooling fixen.
- Wenn Entitlements reduziert werden müssen: Feature-Degradation explizit dokumentieren.
- Wenn Notarization-Probe failt: Fehlerursache nach Kategorie mappen (Signing, Entitlements, Packaging, Policy).

## Offene Punkte

- Wer stellt die finalen Team-/Issuer-Credentials für notarytool bereit?
- Wird Sparkle-Signierung parallel oder nach Notarization-Spike eingeführt?
