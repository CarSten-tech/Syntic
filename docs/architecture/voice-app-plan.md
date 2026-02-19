# Flow Dictation + Command Mode — Architektur & Produktplan

> Sprache: Deutsch. Kein Code, kein Pseudocode. Ausschließlich Planung, Architekturentscheidungen, Risiken und umsetzbares Vorgehen.
> Stand: 2026-02-19

---

## 1. Kurzdefinition & Leitprinzipien

**Was ist die App?**
Eine plattformübergreifende, sprachgesteuerte Productivity-App mit zwei Kernmodi: Flow Dictation (systemweites Diktat mit minimalem Kontextwechsel) und Command Mode (Hotkey-getriggerte Palette für Sprach- und Textbefehle mit lokaler Tool-Ausführung). Zielgruppe: Power User und Enterprise-Kunden mit hohem Anspruch an Datenschutz und Effizienz.

**Leitprinzipien:**

- **macOS-first, nicht macOS-only:** Der MVP wird auf macOS exzellent — nicht nur funktionstüchtig. Portierungen folgen erst, wenn macOS stabil und qualitativ hochwertig ist. Qualität vor Geschwindigkeit der Portierung.
- **Core/Platform-Split von Tag 1:** Jede Business-Logik lebt plattformunabhängig im Core. Plattformspezifischer Code ist explizit als Adapter gekapselt. Kein Rewrite für spätere Plattformen.
- **Security ist kein Feature, sondern ein Default:** Jede Entscheidung beginnt mit der Frage nach dem Angriffspfad. Sicherheit hat Vorrang vor Komfort — wenn UX und Security kollidieren, gewinnt Security mit transparenter Begründung.
- **Privacy by Design:** Minimale Datenerhebung. Nur senden, was zwingend notwendig ist. Kein Tracking ohne explizite Zustimmung. Sensitive Mode als vollständig isolierter Betriebsmodus.
- **Least Privilege durchgängig:** Jede Komponente bekommt nur die Rechte, die sie für ihre Aufgabe benötigt — nicht mehr. Permissions werden schrittweise und erklärend angefordert.
- **Explizit über implizit:** Keine Magic, keine verdeckten Seiteneffekte. Jede Tool-Ausführung mit potenziell destruktiver Wirkung erfordert explizite Nutzerbestätigung.
- **Austauschbare Abhängigkeiten:** Provider (STT, LLM), Speicher und OS-Integrationen sind hinter definierten Interfaces gekapselt. Kein Lock-in auf einen Anbieter.
- **Null Silent Failures:** Fehler werden geloggt, zurückgegeben oder eskaliert — nie verschluckt. Logs sind strukturiert, redaktiert (kein PII, keine Keys) und lokal.
- **Langfristige Wartbarkeit über kurzfristigen Output:** Keine Temporary Solutions, keine TODOs im Code, keine God Objects. Die erste Zeile setzt den Qualitäts-Floor.
- **Native Look & Feel je Plattform:** Die UI respektiert die Designsprache des jeweiligen Betriebssystems. Kein generisches Cross-Platform-Einheitsbrei — macOS fühlt sich wie macOS an.

---

## 2. Produktumfang & User Journeys

Sechs Kernflows decken den vollständigen Produktumfang ab. macOS ist jeweils die primäre Beschreibungsebene. Andere Plattformen werden als Äquivalent oder Workaround benannt, ohne Implementationsdetail.

---

### Flow 1 — Systemweites Diktat in eine fremde App

**Trigger:** Nutzer drückt den konfigurierten Diktat-Hotkey (Standard: `⌥Space`) während er in einer beliebigen App arbeitet (z. B. Mail, Notion, Browser-Textfeld).

**Schritte:**
- Floating Dictation Indicator erscheint sofort nahe dem Cursor oder am unteren Bildschirmrand — minimal, nicht blockierend, zeigt aktive Wellenform
- Mikrofon wird aktiviert, Voice Activity Detection startet
- Gesprochener Text wird in Echtzeit transkribiert und im Indicator als Live-Vorschau angezeigt
- Bei Sprechpause (VAD-gesteuert, konfigurierbare Schwelle) oder erneutem Hotkey-Druck: Transkription abgeschlossen
- Text wird per Accessibility API in das zuvor fokussierte Feld des fremden Prozesses injiziert
- Indicator verschwindet, Fokus kehrt zur ursprünglichen App zurück

**Ergebnis:** Transkribierter Text steht im Zielfeld, als hätte der Nutzer ihn getippt. Kein Kontextwechsel, kein Copy-Paste.

**Fehler- & Fallback-Handling:**
- Kein Mikrofon-Zugriff: Indicator zeigt Fehler-State mit direktem Link zu Systemeinstellungen → Mikrofon-Berechtigung
- Accessibility Permission fehlt: einmalige erklärende Benachrichtigung, dann Fallback auf Clipboard-Einfügen (Text in Zwischenablage + Benutzerhinweis zum manuellen Einfügen)
- Zielfeld akzeptiert keine Injection (z. B. geschütztes Feld, bestimmte Electron-Apps): Fallback auf Clipboard, Nutzer wird informiert
- STT-Fehler / Timeout: Indicator zeigt Fehler, Audio-Puffer wird verworfen, kein partieller Text wird injiziert
- Sensitive Mode aktiv: Cloud-STT deaktiviert, on-device STT erzwungen — falls nicht verfügbar, Fehlermeldung mit Konfigurationslink

**Andere Plattformen:**
- Windows: identisch via SendInput / UI Automation; Explorer-Fokusverlust ist bekanntes Problem, Workaround via Clipboard-Fallback
- Linux (X11): xdotool-äquivalent; Wayland: stark eingeschränkt, Clipboard-Fallback als primärer Weg
- iOS: Keyboard Extension als Custom Keyboard — systemweit nur innerhalb von Apps, die Custom Keyboards zulassen; kein globaler Hotkey möglich
- Android: Input Method Editor (IME) als Custom-Tastatur oder Accessibility Service; systemweiter Hotkey nicht möglich, stattdessen Notification-Action oder Quick Tile

---

### Flow 2 — Command Mode: Sprachbefehl ausführen

**Trigger:** Nutzer drückt den Command-Hotkey (Standard: `⌘⌥Space`). Funktioniert systemweit, unabhängig von der aktiven App.

**Schritte:**
- Command Palette öffnet sich zentriert oben im Bildschirm (Spotlight-ähnlich, NSPanel, schwebt über allen Fenstern) — Erscheinungszeit unter 100 ms
- Mikrofon aktiviert sich automatisch (konfigurierbar: immer / nur auf Knopfdruck)
- Nutzer spricht Befehl oder tippt ihn (beide Eingabewege gleichwertig)
- Live-Transkription erscheint im Palettenfeld während des Sprechens
- Intent-Erkennung via LLM: Befehl wird in strukturierten Intent mit Parametern aufgelöst (z. B. `SET_TIMER duration=25min label="Pomodoro"`)
- Palette zeigt erkannten Intent als lesbare Zusammenfassung zur Bestätigung an: "Timer: 25 Minuten — Pomodoro. Ausführen?"
- Nutzer bestätigt per `Enter` oder Sprache ("Ja") — oder korrigiert
- Tool Runtime führt Aktion aus
- Palette schließt sich, kurze nicht-blockierende Erfolgsbestätigung (Toast, 3 Sekunden)

**Ergebnis:** Aktion ausgeführt, Nutzer ist sofort wieder in seiner ursprünglichen Arbeit.

**Fehler- & Fallback-Handling:**
- Intent nicht erkennbar: Palette zeigt "Nicht verstanden" + Vorschläge ähnlicher Befehle; Nutzer kann korrigieren oder abbrechen
- LLM-Fehler / Timeout: Fallback auf regelbasierte Intent-Erkennung für Standardbefehle (Timer, Notiz); komplexere Befehle zeigen Fehlermeldung mit Retry-Option
- Tool-Ausführungsfehler (z. B. Datei nicht gefunden): Inline-Fehler in der Palette, kein stiller Abbruch
- Nutzer bricht ab: `Escape` schließt Palette, kein Nebeneffekt

**Andere Plattformen:**
- Windows/Linux: identisch, globaler Hotkey via plattformspezifische API
- iOS: kein systemweiter Hotkey — Äquivalent ist ein AppIntent (Siri-Shortcut) oder Widget; innerhalb der App volle Palette verfügbar
- Android: Quick Tile oder Accessibility-Button als Trigger; innerhalb der App volle Palette

---

### Flow 3 — File Action mit Finder-Kontext

**Trigger:** Nutzer hat eine oder mehrere Dateien im Finder selektiert, öffnet dann Command Palette (`⌘⌥Space`) und spricht einen Dateibefehl.

**Schritte:**
- Command Palette öffnet sich
- App liest via AppleScript die aktuelle Finder-Selektion aus (Pfade der selektierten Dateien)
- Palette zeigt Kontext an: "3 Dateien ausgewählt: report.pdf, data.csv, notes.txt"
- Nutzer spricht: "Verschiebe alle in den Ordner Archiv 2025"
- Intent-Erkennung ergibt: `MOVE_FILES sources=[...] destination="~/Archiv 2025"`
- Falls Zielordner nicht existiert: Palette fragt "Ordner 'Archiv 2025' existiert nicht — anlegen?" mit Ja/Nein
- Bestätigung durch Nutzer → Tool Runtime führt Verschiebung aus
- Erfolgsbestätigung: "3 Dateien verschoben nach ~/Archiv 2025"

**Ergebnis:** Dateien liegen am Zielort. Finder aktualisiert sich automatisch.

**Fehler- & Fallback-Handling:**
- Finder ist nicht die frontmost App oder hat keine Selektion: Palette startet ohne Dateikontext; Nutzer kann Pfade manuell eingeben oder per Drag & Drop in Palette ziehen
- Unzureichende Schreibrechte am Ziel: Fehlermeldung mit konkretem Pfad, kein partieller Move
- Aktion ist nicht umkehrbar (z. B. Umbenennen): Undo-Eintrag wird in internem Log festgehalten, Nutzer kann per `⌘Z` in der Palette rückgängig machen (innerhalb der Session)
- AppleScript-Zugriff verweigert (Automation Permission fehlt): einmalige erklärende Anforderung der Permission; ohne Permission kein Dateikontext, manuelle Eingabe als Fallback

**Andere Plattformen:**
- Windows: Shell API / IShellWindows für Explorer-Selektion — technisch möglich, aufwändiger; Phase 2
- Linux: keine standardisierte API; Nautilus/Dolphin via DBus best-effort, sehr fragmentiert; manuelle Pfadeingabe als primärer Weg
- iOS/Android: kein Dateimanager-Kontext möglich; Share Sheet als Äquivalent (Dateien werden aus anderer App geteilt)

---

### Flow 4 — Timer & Reminder setzen

**Trigger:** Nutzer öffnet Command Palette und spricht "Erinnere mich in 20 Minuten, die E-Mail an Klaus zu schreiben."

**Schritte:**
- Intent-Erkennung: `SET_REMINDER delay=20min text="E-Mail an Klaus schreiben"`
- Palette zeigt Bestätigung: "Reminder: In 20 Minuten — E-Mail an Klaus schreiben"
- Nutzer bestätigt
- Tool Runtime registriert Timer lokal (kein Cloud-Dienst, kein Kalender-Zugriff ohne explizite Konfiguration)
- Nach 20 Minuten: macOS-native Benachrichtigung (UserNotifications Framework) erscheint mit Text und "Erledigt"-Aktion

**Ergebnis:** Nutzer erhält zuverlässige, lokale Benachrichtigung ohne Drittdienst.

**Fehler- & Fallback-Handling:**
- Benachrichtigungs-Permission fehlt: Onboarding-Hinweis beim ersten Timer; Timer läuft trotzdem, Benachrichtigung erscheint im App-eigenen Notification Center als Fallback
- App ist beim Fälligkeitszeitpunkt nicht aktiv: LaunchAgent / Background-Daemon stellt sicher, dass Timer auch ohne offenes Hauptfenster feuert
- Gerät war ausgeschaltet / im Schlaf: Timer feuert bei nächstem Aufwachen sofort mit Hinweis auf verpasste Erinnerung

**Andere Plattformen:**
- Windows: Windows Toast Notifications; Background via Windows Task Scheduler oder Service
- Linux: libnotify; systemd user timer oder cron als Daemon-Äquivalent
- iOS/Android: UNUserNotificationCenter (iOS) / AlarmManager (Android); Background stark eingeschränkt, Timer-Genauigkeit abhängig von OS-Doze-Policies

---

### Flow 5 — Ersteinrichtung & BYOK-Onboarding

**Trigger:** App wird zum ersten Mal gestartet.

**Schritte:**
- Schritt 1 — Willkommen: Kurze Value-Prop-Darstellung (ein Screen), keine Walls of Text
- Schritt 2 — Mikrofon-Permission: Erklärung warum ("Diktat und Sprachbefehle"), was gespeichert wird ("Audio nur während aktiver Session im RAM, nicht auf Disk"), Option für Sensitive Mode direkt hier sichtbar → macOS-Permission-Dialog wird ausgelöst
- Schritt 3 — Accessibility-Permission: Erklärung warum ("Text in andere Apps einfügen"), direkter Link zu Systemeinstellungen → Accessibility; App wartet auf Bestätigung und prüft aktiv
- Schritt 4 — Hotkeys: Vorgeschlagene Defaults mit Preview-Animation; Nutzer kann anpassen oder übernehmen
- Schritt 5 — AI Provider: Auswahl (OpenAI / Anthropic / Lokal / Später); bei Cloud-Wahl: Key-Eingabefeld (sofort in Keychain geschrieben, nie im UI-State gehalten); bei Lokal: Hinweis auf Modell-Download in Phase 2; "Später" überspringt — Features ohne LLM sind eingeschränkt, klar kommuniziert
- Schritt 6 — Fertig: Kurze Zusammenfassung der aktiven Berechtigungen und konfigurierten Features

**Ergebnis:** App ist vollständig einsatzbereit. Nutzer kennt seine Konfiguration.

**Fehler- & Fallback-Handling:**
- Permission verweigert: Schritt wird als "eingeschränkt" markiert, Feature-Beschränkung klar kommuniziert; Permission kann jederzeit in App-Settings nachgeholt werden
- Key-Validierung schlägt fehl (ungültiger Key): Inline-Fehler direkt im Eingabefeld, kein Fortfahren ohne validen Key (oder explizites Überspringen)
- Onboarding abgebrochen: Zustand gespeichert, nächster Start setzt an letztem Schritt fort

**Andere Plattformen:** Identischer Flow, je nach Plattform mit angepassten Permission-Dialogen und Verlinkungen zu den jeweiligen Systemeinstellungen.

---

### Flow 6 — Sensitive Mode aktivieren

**Trigger:** Nutzer aktiviert Sensitive Mode in den App-Einstellungen (oder bereits im Onboarding).

**Schritte:**
- Toggle "Sensitive Mode" → Bestätigungsdialog: "Was ändert sich?" (keine Cloud, kein Logging, kein Telemetrie, nur lokale Modelle)
- Bestätigung → App wechselt sofort in Sensitive Mode
- Menu Bar Icon ändert Erscheinungsbild (subtiler visueller Indikator, z. B. Schloss-Symbol oder Farbe)
- Alle laufenden Cloud-Verbindungen werden beendet
- Existierende lokale Logs werden auf Wunsch gelöscht (explizite Auswahl, nicht automatisch)
- LLM-Features ohne lokales Modell werden als "nicht verfügbar im Sensitive Mode" angezeigt — kein stiller Ausfall

**Ergebnis:** Vollständige lokale Isolation. Kein Byte verlässt das Gerät ohne Nutzeraktion.

**Fehler- & Fallback-Handling:**
- Kein lokales STT-Modell verfügbar: Diktat-Feature deaktiviert mit klarem Hinweis und Link zu Modell-Download (Phase 2)
- Kein lokales LLM verfügbar: Command Mode beschränkt auf regelbasierte Erkennung (Timer, Notiz, einfache File-Ops ohne NL-Verständnis)
- Sensitive Mode versehentlich aktiviert: einfaches Deaktivieren möglich, kein Datenverlust
