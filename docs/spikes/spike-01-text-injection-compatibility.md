# Spike 01 — Text Injection Kompatibilität (macOS)

Status: In Arbeit  
Datum: 2026-02-19  
Owner: Syntic Core Team

## Ziel

Verifizieren, welche Injection-Methode pro Ziel-App im MVP robust funktioniert:

- `AXUIElementSetAttributeValue` (AX)
- `CGEventPost` mit Unicode-Keyevents (CGEvent)
- Clipboard-Fallback (nur wenn AX/CGEvent scheitern)

## Erfolgsdefinition

Die Spike-Ergebnisse sind ausreichend, wenn folgende Punkte erfüllt sind:

- Für jede Test-App ist eine primäre Methode festgelegt (`AX` oder `CGEvent` oder `Clipboard-only`).
- Bekannte Ausnahmen sind dokumentiert (z. B. keine Injection in Passwortfelder).
- Entscheidung für MVP-Fallback-Regel ist getroffen.

## Testumgebung

- macOS Ventura 13.7.x
- Syntic Spike Lab aus `apps/macos` (Fenster: `Spike Lab`)
- Berechtigungen:
  - Accessibility erlaubt
  - Input Monitoring erlaubt (falls CGEvent nötig)

## Testfälle

Pro App jeweils mit Text:

- `Syntic Spike DE: äöü ß 123`
- `Syntic Spike EN: test punctuation !?.,`

Methoden pro App:

1. AX Injection
2. CGEvent Injection
3. Clipboard manuell als Kontrollfall

## Ziel-Apps (aus Architekturplan)

- TextEdit (Cocoa)
- Safari (WebKit)
- Google Chrome (Chromium)
- Notion (Web/Electron)
- Slack (Electron)
- VS Code (Electron)
- Microsoft Word (Office)
- Figma (Electron)

## Ergebnis-Matrix

| App | AX | CGEvent | Clipboard | Primär im MVP | Notes |
|---|---|---|---|---|---|
| TextEdit | TBD | TBD | TBD | TBD | |
| Safari | TBD | TBD | TBD | TBD | |
| Chrome | TBD | TBD | TBD | TBD | |
| Notion | TBD | TBD | TBD | TBD | |
| Slack | TBD | TBD | TBD | TBD | |
| VS Code | TBD | TBD | TBD | TBD | |
| Word | TBD | TBD | TBD | TBD | |
| Figma | TBD | TBD | TBD | TBD | |

## Entscheidungsregeln

- AX erfolgreich und stabil: `AX` als primäre Methode für diese App.
- AX unzuverlässig, CGEvent stabil: `CGEvent` als primäre Methode.
- Beide unzuverlässig oder blockiert: `Clipboard` als Primär-Fallback.

## MVP-Entscheidung (auszufüllen)

- Globaler Default: `AX first`, fallback `CGEvent`, fallback `Clipboard`.
- App-spezifische Overrides:
  - TBD

## Offene Punkte

- Input Monitoring Fehlermeldung klar im UI anzeigen.
- Passwortfelder und secure inputs explizit sperren.
- Retry-Strategie bei Fokuswechsel zwischen Hotkey und Injection finalisieren.
