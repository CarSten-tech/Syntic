# MVP-Scope — Syntic

> Sprache: Deutsch. Verbindliche Scope-Definition für den macOS MVP.
> Stand: 2026-02-19
> Basiert auf: `docs/architecture/voice-app-plan.md` Punkt 10 (Entscheidungsprotokoll)

Dieses Dokument ist der Implementierungsvertrag für den MVP. Alles unter **Im Scope** muss fertig und qualitätsgeprüft sein, bevor der MVP als abgeschlossen gilt. Alles unter **Nicht im Scope** darf nicht implementiert werden — weder als "Quick Win" noch als Vorbereitung.

---

## Architektur-Constraints (nicht verhandelbar)

Diese Constraints folgen direkt aus dem Entscheidungsprotokoll und gelten für jeden Commit im MVP:

- **Kein Backend, kein Server, kein Account-System** — die App funktioniert vollständig lokal und offline (außer beim Aufruf externer AI-Provider durch den Nutzer selbst)
- **MIT Open Source** — kein Code, der nicht unter MIT lizenziert werden kann; Dependency-Audit auf GPL-Kompatibilität vor jeder neuen Abhängigkeit
- **BYOK-Pflicht** — kein eingebetteter AI-Provider-Key; der Nutzer bringt eigene Keys mit; Keys landen ausschließlich im lokalen macOS Keychain
- **Kein silent Injizieren** — jeder STT-Output wird dem Nutzer in einer Vorschau angezeigt und muss bestätigt werden, bevor Text in eine andere App injiziert wird
- **Keine destruktiven Aktionen ohne Bestätigung** — File-Move bei Überschreiben, File-Rename auf existierenden Namen, jede Operation die nicht umkehrbar ist, erfordert einen expliziten Confirm-Schritt
- **macOS 13 Ventura als Minimum** — keine API-Aufrufe ohne Ventura-Fallback; Sonoma-spezifische Optimierungen sind opt-in und müssen hinter `#available(macOS 14, *)` Guards liegen
- **Deutsch + Englisch gleichzeitig** — keine sprachabhängige Intent-Erkennung per Regex; alle Intents sind semantisch und sprachunabhängig

---

## Im Scope: Feature-Blöcke

### Block 1 — Flow Dictation

Globales systemweites Diktat in jede App.

**Was ist fertig wenn:**
- Hotkey `⌥Space` (konfigurierbar) triggert den Dictation-Flow aus jeder App heraus
- Floating Dictation Indicator erscheint nahe dem aktiven Cursor oder am Bildschirmrand — nicht blockierend
- Mikrofon-Aktivierung mit sofortiger visueller Wellenform-Anzeige
- Live-Transkription im Indicator sichtbar während der Nutzer spricht
- VAD (Voice Activity Detection) erkennt Sprechpause und schließt die Transkription ab; alternativ zweiter Hotkey-Druck
- **Korrektur-Flow:** transkribierter Text bleibt im Indicator editierbar; Nutzer bestätigt explizit (Enter oder Klick) oder verwirft (Escape)
- Nach Bestätigung: Text-Injection in das zuvor fokussierte Feld via Accessibility API
- Fallback bei fehlendem Accessibility-Permission: Clipboard-Injection mit einmaliger erklärender Benachrichtigung
- Indicator verschwindet nach Abschluss; Fokus kehrt zur ursprünglichen App zurück
- Fehler-States haben eigene visuelle Behandlung: kein Mikrofon, keine Berechtigung, STT-Fehler, Netzwerkfehler (bei Cloud-STT)

**Grenze:**
- Kein fortlaufendes "immer an"-Diktat (Push-to-Talk-Modell bleibt im MVP)
- Keine Echtzeit-Übersetzung
- Kein Diktat direkt in native macOS-Felder (TextEdit, Pages) über den App-eigenen Mechanismus — Accessibility-Injection gilt für alle Apps gleich

---

### Block 2 — Command Mode

Hotkey-getriggerte Befehlspalette für Sprach- und Textbefehle.

**Was ist fertig wenn:**
- Separater Hotkey `⌥K` (konfigurierbar) öffnet die Command Palette
- Palette akzeptiert Eingabe per Sprache (STT) oder direkt per Text (Tastatur)
- Intent-Klassifikation läuft im Rust-Core; erkennt Sprache automatisch (DE/EN)
- Erkannter Intent und extrahierte Parameter werden als strukturierter Vorschlag angezeigt, bevor die Aktion ausgeführt wird
- Nutzer bestätigt oder verwirft jeden Befehl — kein Auto-Execute
- Unbekannte Intents zeigen Fehlerzustand mit verständlicher Meldung, nicht stillen Fehler
- Escape schließt die Palette jederzeit ohne Seiteneffekte

**Grenze:**
- Kein mehrstufiger Konversations-Dialog (Command Mode ist stateless — ein Befehl, eine Aktion)
- Kein Command History Browse im MVP (später)

---

### Block 3 — Tool-Set

Die Menge der Aktionen, die der Command Mode ausführen kann.

**Alle Tools erfordern explizite Nutzerbestätigung bevor Ausführung.**

#### Dateioperationen

| Tool | Beschreibung | Reversibel |
|------|--------------|------------|
| `FileMove` | Datei oder Ordner von A nach B verschieben | Nein — Bestätigung verpflichtend; Überschreiben nur mit zweitem Confirm |
| `FileCopy` | Datei oder Ordner kopieren | Ja |
| `FileRename` | Datei oder Ordner umbenennen | Nein — Bestätigung verpflichtend |
| `DirectoryCreate` | Neuen Ordner erstellen | Ja (Ordner kann gelöscht werden) |

**Nicht im MVP:**
- Löschen (zu destruktiv ohne Papierkorb-Integration)
- ZIP/Archivieren, Entpacken
- Batch-Umbenennen mit Mustern
- PDF-Merge, Media Convert (Phase 2)

#### System / App-Steuerung

| Tool | Beschreibung |
|------|--------------|
| `AppLaunch` | Installierte App per Name oder Bundle-ID öffnen |
| `OpenUrl` | URL im Standard-Browser öffnen; nur validierte URLs; kein javascript:-Schema |

#### Clipboard

| Tool | Beschreibung |
|------|--------------|
| `ClipboardRead` | Aktuellen Clipboard-Inhalt lesen (Text) |
| `ClipboardWrite` | Text in Clipboard schreiben |

#### Notizen

| Tool | Beschreibung |
|------|--------------|
| `NoteSave` | Markdown-Datei in konfiguriertem Notizen-Ordner speichern; Dateiname aus Titel oder Timestamp |

**Nicht im MVP:** Obsidian-Integration, Apple Notes, Notion, Bear.

#### Kalender / Reminders

| Tool | Beschreibung |
|------|--------------|
| `ReminderCreate` | Reminder in Apple Reminders erstellen (EventKit-Schreibberechtigung); optionaler Termin |

**Nicht im MVP:** Kalender-Events lesen, bestehende Termine abfragen, Kalender-Events bearbeiten oder löschen.

#### Shell (eingeschränkt)

| Tool | Beschreibung |
|------|--------------|
| `ShellCommand` | Vordefinierten Shell-Befehl ausführen (Allowlist-basiert, kein freier Shell-Input) |

Wichtig: `ShellCommand` akzeptiert keinen freien Nutzereingabe-String als Shell-Befehl — das wäre eine Command-Injection-Oberfläche. Es gibt eine konfigurierte Allowlist von Befehlen mit festen Parametern. Freie Shell-Ausführung ist Post-MVP und erfordert eine eigene Sicherheitsanalyse.

---

### Block 4 — STT-Provider

| Provider | Typ | Konfiguration |
|----------|-----|---------------|
| `AppleSpeechRecognizer` | Lokal, kostenlos, kein Key notwendig | Locale muss explizit gesetzt sein (de-DE / en-US); On-Device-Flag gesetzt wo verfügbar |
| `OpenAIWhisper` | Cloud, BYOK | API-Key im Keychain; Modell konfigurierbar; Kosten-Schätzung in Settings angezeigt |

**Was ist fertig wenn:**
- Nutzer wählt Default-STT-Provider in Settings
- Provider-Wechsel ist ohne App-Neustart wirksam
- Bei Cloud-Provider: API-Key-Eingabe in Settings → Speicherung im Keychain → nie im Log, nie in UserDefaults
- Settings zeigt: Provider-Typ (lokal/cloud), aktives Modell, geschätzte Kosten pro Minute (bei Cloud), letzten Verbindungstest
- Verbindungstest-Button in Settings prüft Erreichbarkeit und Key-Validität
- Fehler bei STT-Aufruf werden im UI kommuniziert (nicht still verschluckt)

**Nicht im MVP:**
- Deepgram, AssemblyAI, oder andere STT-Provider
- Selbst-gehostetes Whisper (Milestone 3)
- Automatischer Provider-Wechsel bei Fehler (Fallback-Kette)

---

### Block 5 — LLM-Provider (Intent-Klassifikation)

| Provider | Typ | Konfiguration |
|----------|-----|---------------|
| `Ollama` | Lokal, kostenlos, kein Key | Ollama-URL konfigurierbar (Standard: `http://localhost:11434`); Modell wählbar |
| `OpenAIChatCompletion` | Cloud, BYOK | API-Key im Keychain; Modell konfigurierbar (Standard: `gpt-4o-mini`) |

**Was ist fertig wenn:**
- Intent-Klassifikation ist sprachunabhängig (DE + EN ohne separate Prompt-Pfade)
- Nutzer wählt Default-LLM-Provider in Settings
- Bei Cloud-Provider: gleiche Key-Behandlung wie STT (Keychain, nie geloggt)
- Ollama-Verbindungstest in Settings
- Wenn kein LLM konfiguriert und Befehl kommt: klare Fehlermeldung "LLM-Provider nicht konfiguriert" — kein Crash, kein silent Fail
- LLM-Prompt enthält keine Nutzerdaten außer dem Intent-Text; kein Kontext-Leaking

**Nicht im MVP:**
- Anthropic Claude, Gemini, Mistral als direkte Provider
- LLM-basierte Antwortgenerierung (die App führt aus, sie antwortet nicht in natürlicher Sprache)
- Konversations-History (Context Window über mehrere Befehle hinweg)

---

### Block 6 — Settings UI

**Was ist fertig wenn:**
- Menu Bar Icon als primärer App-Einstiegspunkt (keine Dock-Präsenz, keine Hauptfenster-Dominanz)
- Settings-Fenster erreichbar über Menu Bar → Settings
- Abschnitte: Hotkeys, STT-Provider, LLM-Provider, Dateioperationen (Standard-Pfade), Notizen (Ordner-Pfad), Allgemein (Sprache, Autostart)
- Jede Einstellung speichert sofort (kein "Save"-Button notwendig)
- API-Keys werden maskiert angezeigt (●●●●); separater "Key anzeigen"-Toggle mit Passwort-Bestätigung
- STT-Kosten-Anzeige: "Lokal — kostenlos" vs. "Cloud — ca. $X / Stunde (Whisper-Preisliste)"
- Autostart beim Login konfigurierbar (LaunchAgent)
- Reset-auf-Werkseinstellungen mit expliziter Bestätigung (separater Confirm-Schritt)

---

### Block 7 — Berechtigungen & Onboarding

**Was ist fertig wenn:**
- Beim ersten Start: schrittweiser Permission-Flow
  1. Mikrofon-Berechtigung — erklärender Text warum notwendig
  2. Accessibility-Berechtigung — erklärender Text warum notwendig, direkter Link zu Systemeinstellungen
  3. Reminders-Berechtigung — nur wenn ReminderCreate-Tool genutzt wird (Just-in-Time)
- Jede Berechtigung wird mit verständlichem Nutzen erklärt — nie technischer Jargon
- App ist nach abgelehnter Accessibility-Berechtigung weiterhin nutzbar (Clipboard-Fallback)
- Permission-Status in Settings sichtbar mit "Neu anfragen"-Link

---

### Block 8 — Logging & Fehlerbehandlung

**Was ist fertig wenn:**
- Strukturiertes JSON-Logging lokal auf dem Gerät
- Log-Level: ERROR, WARN, INFO, DEBUG (DEBUG standardmäßig deaktiviert)
- Kein PII in Logs: keine transkribierten Texte, keine API-Keys, keine Dateipfade mit Nutzerdaten
- Log-Rotation: max. 7 Tage, max. 50 MB
- Unbehandelte Exceptions werden geloggt mit vollständigem Kontext (kein Crash ohne Log)
- Logs abrufbar über Settings → "Logs öffnen" (öffnet Log-Ordner im Finder)

---

## Nicht im Scope (MVP)

Diese Punkte sind explizit ausgeschlossen. Keine Exceptions ohne Revision des Entscheidungsprotokolls.

| Feature | Begründung für Ausschluss |
|---------|--------------------------|
| User-Accounts / Backend | Entscheidung: vollständig lokal, kein Server |
| Multi-Device Sync | Entscheidung: kein Sync im MVP |
| Kalender-Events lesen | Zu komplex für MVP; andere Architekturfragen |
| iCloud / Dropbox / Notion / Obsidian / Bear Integration | Post-MVP Plugin; kein API-Overhead im Core |
| PDF-Merge, Media-Konvertierung | Phase 2 nach MVP-Stabilisierung |
| Datei-Löschen | Irreversibel; Papierkorb-Integration zu komplex |
| ZIP / Archivieren / Entpacken | Nicht im Kern-Anwendungsfall |
| Batch-Umbenennen mit Mustern | Separates Feature, eigener Scope |
| Freier Shell-Input | Command-Injection-Risiko; erst nach Sicherheitsanalyse |
| Konversations-Dialog (mehrstufig) | Command Mode ist stateless — bewusste Entscheidung |
| Command History Browser | Post-MVP |
| Automatischer Provider-Fallback | Zu komplex; explizite Fehler sind besser |
| Selbst-gehostetes Whisper | Milestone 3 |
| Anthropic / Gemini / Mistral als Provider | Post-MVP |
| Apple Notarization | Vor Public Beta; nicht für Development-Build |
| Sensitive Mode | Milestone 2 |
| Enterprise-Features (SSO, MDM, Audit) | Milestone 6 |
| Windows / Linux | Milestone 2a/2b |
| iOS / Android | Milestone 4a/4b |
| Plugin SDK | Milestone 5 |
| Telemetrie / Crash-Reporting zu externem Service | Erst wenn opt-in Infrastruktur vorhanden; nicht im MVP |
| Dark Mode (vollständig) | System-Appearance wird respektiert; eigenes Dark-Mode-Design-System Post-MVP |

---

## MVP-Qualitätsgates

Der MVP gilt als abgeschlossen wenn **alle** folgenden Kriterien erfüllt sind:

### Funktional
- [ ] Flow Dictation funktioniert in mindestens 10 verschiedenen macOS-Apps (Browser, Mail, Slack, Terminal, Notion, etc.)
- [ ] Clipboard-Fallback funktioniert korrekt wenn Accessibility-Berechtigung fehlt
- [ ] Command Mode erkennt alle 11 Tool-Intents korrekt auf DE und EN (Testmatrix vorhanden)
- [ ] Alle 11 Tools führen ihre Aktionen korrekt aus und zeigen Bestätigungsdialog
- [ ] STT-Provider-Wechsel funktioniert ohne App-Neustart
- [ ] LLM-Provider-Wechsel funktioniert ohne App-Neustart
- [ ] API-Key wird korrekt im Keychain gespeichert und nie in Logs ausgegeben (verifizierbarer Test)
- [ ] STT-Korrektur-Flow (Vorschau → Edit → Bestätigen / Verwerfen) funktioniert vollständig
- [ ] Settings: alle Einstellungen persistieren korrekt nach App-Neustart

### Robustheit
- [ ] Kein Crash bei: Mikrofon nicht verfügbar, Accessibility Permission fehlt, API-Key ungültig, Netzwerk nicht erreichbar, leerer Transkription, unbekanntem Intent
- [ ] Alle Fehler-States haben eine visuelle Behandlung im UI — kein weißer Bildschirm, kein leeres Fenster
- [ ] App startet korrekt auf macOS 13.7.x (Ventura) und macOS 14.x (Sonoma)

### Sicherheit
- [ ] Kein API-Key in Logs, UserDefaults, Dateisystem oder Clipboard
- [ ] ShellCommand-Tool akzeptiert keine freien Nutzereingaben als Shell-Befehl
- [ ] Accessibility-Injection injiziert keinen Text ohne explizite Nutzerbestätigung
- [ ] Dependency-Audit: `cargo audit` ohne kritische CVEs

### Code-Qualität
- [ ] `cargo clippy -- -D warnings` — null Warnings
- [ ] `swiftlint` — null Errors
- [ ] Unit-Tests für Intent-Klassifikation mit Testmatrix (DE + EN, alle Intents)
- [ ] Unit-Tests für alle File-Tools (mock Dateisystem)
- [ ] Integration-Tests für STT- und LLM-Provider-Adapter (gegen echte Testumgebung oder VCR-Cassettes)

---

## Nächste Iteration (Post-MVP / Milestone 1)

Diese Features sind nach MVP-Abschluss die erste Priorität — dokumentiert damit sie nicht vergessen werden und nicht in den MVP-Scope schleichen:

| Feature | Warum Post-MVP |
|---------|---------------|
| Vollständiges Dark-Mode Design-System | Benötigt Design-Token-System; MVP respektiert nur System-Appearance |
| Apple Notarization & Sparkle Auto-Update | Vor Public Beta notwendig |
| Command History Browser | UX-Verbesserung nach MVP-Feedback |
| Automatischer STT-Provider-Fallback | Erst wenn Basis stabil |
| Selbst-gehostetes Whisper (Core ML / llm.cpp) | Milestone 3 Vorarbeit |
| Sensitive Mode (vollständige Process-Isolation) | Sicherheitsfeature nach MVP-Verifikation |
| Obsidian/Notion Plugin (NoteSave-Adapter) | Post Plugin SDK |
| Kalender-Events lesen | Eigener Feature-Scope |
| PDF-Merge, Media Convert | Eigener Feature-Scope |
