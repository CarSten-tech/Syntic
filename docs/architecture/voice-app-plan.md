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

---

## 3. Technische Plattformstrategie

Vier Kandidaten werden vollständig bewertet. Die Bewertungskriterien sind identisch für alle Optionen. Am Ende folgt eine explizite Entscheidung mit Begründung und Plan B.

---

### Kandidat A — Rust Core Library + Platform-Native UI Shells

**Grundprinzip:** Ein in Rust geschriebener Core (Business Logic, Audio, STT, LLM, Tool Runtime, Datenhaltung) wird als native Bibliothek in plattformspezifische UI-Shells eingebunden. Auf macOS ist das SwiftUI + AppKit, auf Windows WinUI 3, auf Linux GTK4, auf iOS SwiftUI, auf Android Jetpack Compose.

- **Globale Hotkeys:** Vollständig native Lösung pro Plattform. macOS: CGEventTap via Swift-Adapter, zuverlässigste Option ohne Sandbox-Einschränkungen. Windows: RegisterHotKey via Win32-Adapter. Linux X11: XGrabKey. Qualität: maximal.
- **Systemweite Texteingabe:** macOS: Accessibility API direkt aus Swift-Adapter aufrufbar — kein Umweg. Windows: SendInput / UIA direkt. Qualität: maximal, weil kein Framework-Layer dazwischen.
- **Finder/Explorer-Kontext:** macOS: AppleScript via NSAppleScript aus Swift-Adapter — direkte native Integration. Windows: Shell COM API aus WinUI-Adapter. Qualität: maximal.
- **Background Services/Daemons:** macOS: LaunchAgent als eigenständiger Prozess, aus Swift-Shell gestartet und überwacht. Keine Framework-Einschränkungen. Qualität: maximal.
- **Update-Mechanismus:** Sparkle Framework (macOS, etablierter Standard — Raycast, Alfred, etc.), WinSparkle (Windows), AppImageUpdate (Linux). Je Plattform bewährt, mit Delta-Updates und EdDSA-Signierung.
- **Sicherheits- und Sandbox-Modell:** Hardened Runtime + Notarization auf macOS ohne App Store Sandbox. Entitlements werden minimal gesetzt. Rust-Core ist memory-safe by design. Kein Webview, kein JavaScript, keine zusätzliche Angriffsfläche.
- **Wartbarkeit/Teamgröße:** Hoher initialer Aufwand: jede Plattform-UI-Shell ist separater Codestand. Für ein kleines Team (1–3 Personen) ist Phase 1 (macOS) sehr gut handhabbar; Phase 2 (Windows) erfordert substanzielle Zusatzarbeit. Long-term: wartbar, weil jede Schicht klar getrennt und testbar ist.
- **macOS-Integrationsqualität:** Höchstmöglich. NSStatusItem, NSPanel, NSAppleScript, CGEventTap — alles direkt ohne Adapter-Overhead. App fühlt sich zu 100 % nativ an.

**Gesamtbewertung:** Höchste Qualität und Sicherheit, höchster initialer Aufwand, klar definierter Portierungspfad. Für macOS-first die beste Wahl.

---

### Kandidat B — Tauri v2 (Rust + WebView)

**Grundprinzip:** Rust-Backend für Logic und OS-Zugriff, WebView (WKWebView auf macOS, WebView2 auf Windows, WebKitGTK auf Linux) für UI. Tauri v2 unterstützt auch iOS und Android mit demselben Web-Frontend.

- **Globale Hotkeys:** Tauri-Plugin vorhanden (tauri-plugin-global-shortcut). Auf macOS funktional, aber die Zuverlässigkeit in Edge-Cases (z. B. Gaming-VMs, bestimmte Fullscreen-Apps) ist schlechter dokumentiert als nativer CGEventTap. Funktional ausreichend für MVP.
- **Systemweite Texteingabe:** Erfordert Custom Native Plugin (Rust + Swift-Bridge für macOS). Möglich, aber nicht out-of-the-box — jede Plattform braucht einen eigenen Plugin. Der Aufwand ist ähnlich wie bei Kandidat A, nur weniger direkt.
- **Finder/Explorer-Kontext:** Ebenfalls Custom Native Plugin notwendig. Kein Vorteil gegenüber A, eher Nachteil wegen Plugin-Layer-Overhead.
- **Background Services/Daemons:** Tauri unterstützt Background-Prozesse, aber die Kontrolle über LaunchAgents auf macOS liegt außerhalb des Frameworks — muss manuell gemacht werden. Kein Nachteil, nur expliziter Mehraufwand.
- **Update-Mechanismus:** Tauri hat eingebautes Updater-System mit Signierung. Gut integriert, zuverlässig.
- **Sicherheits- und Sandbox-Modell:** WebView ist eine signifikante zusätzliche Angriffsfläche. Content Security Policy muss sorgfältig konfiguriert werden. JavaScript-Bridge zum Rust-Backend ist ein kritischer Grenzpunkt, der explizite Validierung erfordert. Hardened Runtime + Notarization möglich, aber WebView-Entitlement erhöht Angriffsfläche.
- **Wartbarkeit/Teamgröße:** Für web-affine Teams sehr produktiv — Frontend-Entwickler können sofort beitragen. Ein UI-Codestand für alle Plattformen. Langfristig: WebView-Updates (Chromium/WebKit) sind extern kontrolliert und können Verhalten ändern.
- **macOS-Integrationsqualität:** Mittel. Menu Bar funktioniert, aber native Anmutung hängt stark von CSS-Qualität ab. Kein echtes NSPanel-Feeling out-of-the-box. Kann sehr gut werden, erfordert aber erheblichen CSS-Aufwand. Electron-artige Wahrnehmungsrisiken beim Nutzer.

**Gesamtbewertung:** Guter Kompromiss für web-affine Teams. Schlechtere Sicherheitseigenschaften durch WebView-Layer. macOS-Integrationsqualität erreichbar, aber nicht automatisch. Geeignet als Plan B.

---

### Kandidat C — Flutter

**Grundprinzip:** Dart als Sprache, eigene Rendering-Engine (Impeller/Skia), plattformübergreifendes UI-Framework. Platform Channels für native OS-Zugriffe.

- **Globale Hotkeys:** Kein offizielles Plugin mit ausreichender macOS-Qualität. Community-Plugins existieren, sind aber nicht production-grade. Eigene Platform-Channel-Implementierung notwendig — ähnlicher Aufwand wie Kandidat A.
- **Systemweite Texteingabe:** Platform Channel zu Swift/ObjC notwendig. Technisch machbar, aber jeder OS-Zugriff erfordert nativen Bridging-Code. Kein struktureller Vorteil gegenüber A.
- **Finder/Explorer-Kontext:** Platform Channel notwendig. Identische Situation wie bei Text Injection.
- **Background Services/Daemons:** Flutter-Apps haben keinen nativen Daemon-Support. Background-Prozess muss als separates Binary implementiert und aus dem Flutter-Prozess gestartet werden. Umständlich.
- **Update-Mechanismus:** Kein eingebautes System. Externe Lösung (Sparkle, WinSparkle) notwendig. Mehr Eigenaufwand.
- **Sicherheits- und Sandbox-Modell:** Flutter rendert in eigenes Canvas (kein WebView) — geringere Angriffsfläche als Tauri. Hardened Runtime + Notarization möglich. Platform Channels sind kritische Grenzpunkte wie bei Tauri.
- **Wartbarkeit/Teamgröße:** Dart ist eine kleine Sprache mit kleiner Community im Desktop-Bereich. macOS-Desktop-Flutter ist wesentlich weniger battle-tested als mobil. Langfristig-Risiko: Flutter-Desktop ist bei Google nicht die primäre Zielplattform.
- **macOS-Integrationsqualität:** Niedrig bis mittel. Flutter rendert alles selbst — Menu Bar, NSPanel, native Schriften, native Scroll-Physics sind allesamt Workarounds oder sehen subtil falsch aus. Für eine Productivity-App, die sich nativ anfühlen muss, ist das ein substanzielles Problem.

**Gesamtbewertung:** Für mobile-first sinnvoll, für macOS-first Desktop-Anwendungen mit tiefer OS-Integration ungeeignet. Abgelehnt.

---

### Kandidat D — Qt 6

**Grundprinzip:** C++ (oder Python via PyQt/PySide), eigene Rendering-Engine, reife Cross-Platform-Lösung, seit Jahrzehnten bewährt auf Desktop.

- **Globale Hotkeys:** Qt hat QHotkey-ähnliche Lösungen, aber die macOS-Qualität ist weniger direkt als nativer CGEventTap. Funktional ausreichend.
- **Systemweite Texteingabe:** QAccessibleBridge und plattformspezifische Erweiterungen notwendig. Technisch machbar.
- **Finder/Explorer-Kontext:** macOS: QProcess + AppleScript-Aufruf. Unelegant, aber funktional.
- **Background Services/Daemons:** Qt-Apps können als Daemon laufen, aber LaunchAgent-Verwaltung ist außerhalb von Qt. Kein Nachteil, expliziter Mehraufwand.
- **Update-Mechanismus:** Qt Installer Framework oder externe Lösung. Komplex, veraltete UX.
- **Sicherheits- und Sandbox-Modell:** Kein WebView per default — ähnlich sicher wie Kandidat A. C++ bringt jedoch Memory-Safety-Risiken, die Rust vermeidet. Hardened Runtime + Notarization möglich.
- **Wartbarkeit/Teamgröße:** C++ ist schwer zu beherrschen, fehleranfällig. Python-Bindings (PyQt) sind lizenzrechtlich heikel (GPL vs. kommerziell). Qt-Lizenzkosten (kommerziell) sind erheblich. Langfristig: hohe Maintenance-Kosten.
- **macOS-Integrationsqualität:** Mittel. Qt-Apps sehen auf macOS "fast nativ" aus, aber Details (Schrift-Rendering, native Dialoge, Dark Mode, Scroll-Physics) sind immer leicht off. Für eine Productivity-App ist das wahrnehmbar.

**Gesamtbewertung:** Bewährt, aber für dieses Projekt nicht optimal. C++ Memory-Safety-Risiken, Lizenzkosten, suboptimale macOS-Anmutung. Abgelehnt.

---

### Entscheidung

**Gewählt: Kandidat A — Rust Core Library + Platform-Native UI Shells.**

Begründung:
- macOS-first erfordert maximale native Integration — nur Kandidat A liefert das ohne Kompromisse
- Rust-Core ist memory-safe, auditierbar und testbar ohne OS-Abhängigkeiten — ideal für Security-kritische Operationen (Audio-Buffer, Key-Handling, LLM-Client)
- Der Core/Platform-Split ist strukturell erzwungen, nicht nur eine Konvention — Portierung auf Windows (Phase 2) bedeutet neue UI-Shell + vorhandener Core, kein Rewrite
- Keine externe Rendering-Engine, kein WebView, keine JavaScript-Bridge — minimale Angriffsfläche
- Langfristig: jede Schicht unabhängig testbar, austauschbar, skalierbar

Akzeptierter Nachteil: Pro Plattform eine eigene UI-Shell. Für Phase 1 (macOS) ist das kein Problem. Phase 2 (Windows) erfordert dedizierte Ressourcen. Dieses Risiko ist bekannt und eingeplant.

**Plan B: Kandidat B — Tauri v2.**

Wenn das Team überwiegend web-affin ist und die Time-to-Market kritisch wird, ist Tauri v2 der sinnvolle Rückfall. Die Entscheidung zu Tauri kann nach dem macOS-MVP getroffen werden, wenn abzusehen ist, dass native Windows/Linux-UI-Shells nicht rechtzeitig realisierbar sind. Tauri erlaubt es, den Rust-Core ohne Änderungen weiterzuverwenden und nur die UI-Schicht zu tauschen. Der Sicherheitsabstrich durch den WebView ist dokumentiert und akzeptierbar, wenn CSP und die Rust-Bridge sauber implementiert sind.

---

## 4. Zielarchitektur

Die Architektur ist in zwei strikt getrennte Schichten organisiert: den **plattformunabhängigen Core** (Rust) und die **Platform Adapters + UI Shell** (je Plattform nativ). Alle Abhängigkeiten zeigen von außen nach innen — kein Core-Modul kennt plattformspezifischen Code.

```
┌──────────────────────────────────────────────┐
│              Platform Layer (nativ)          │
│  UI Shell · Hotkey Adapter · OS Adapters     │
├──────────────────────────────────────────────┤
│              Core (Rust)                     │
│  Orchestration · STT · LLM · Tools · Data   │
└──────────────────────────────────────────────┘
```

---

### Modul 1 — Core vs. Platform Adapters

**Core (Rust-Bibliothek, plattformunabhängig):**
- Enthält ausnahmslos alle Business-Regeln, Datenmodelle, Orchestrierungslogik und Zustandsmaschinen
- Exponiert eine klar typisierte FFI-Schnittstelle (C-ABI) nach außen — keine nativen Typen durchdringen die Grenze
- Hat keine Kenntnis von UI, OS-APIs, Dateisystempfaden außerhalb der abstrakten Tool-Schnittstelle oder Netzwerk-Implementierungsdetails
- Jede externe Abhängigkeit (STT-Provider, LLM-Provider, Keychain, Dateisystem) ist als abstraktes Interface definiert — der Core ruft Interfaces auf, nie konkrete Implementierungen

**Platform Adapters (nativ, je Plattform):**
- Implementieren die vom Core definierten Interfaces für den jeweiligen OS-Kontext
- macOS-Adapters: `KeychainAdapter` (Security.framework), `GlobalHotkeyAdapter` (CGEventTap), `TextInjectionAdapter` (AX API), `FinderSelectionAdapter` (NSAppleScript), `NotificationAdapter` (UserNotifications), `AudioCaptureAdapter` (AVFoundation / CoreAudio)
- Adapters haben keine eigene Business-Logik — sie übersetzen nur zwischen OS-APIs und Core-Interfaces
- Jeder Adapter ist einzeln testbar (gegen Mock-Core-Interface)

**Grenzregel:** Kein Adapter-Code im Core. Kein Core-Code in Adaptern, der nicht über das Interface-Protokoll läuft. Verletzungen dieser Regel sind Architektur-Bugs.

---

### Modul 2 — UI Shell (macOS: SwiftUI + AppKit)

**Verantwortlichkeit:** Darstellung aller visuellen Zustände, Entgegennahme von Nutzereingaben, Weiterleitung an Core-Events. Keine Business-Logik.

- Besteht aus drei unabhängigen Fensterkontexten: Menu Bar Popover (Status + Schnellaktionen), Command Palette (NSPanel, systemweit schwebend), Settings-Fenster (reguläres NSWindow)
- Alle UI-Zustände sind vom Core-Zustand abgeleitet — die UI ist eine pure Projektion des Core-State, kein eigenständiger Zustand
- Reagiert auf State-Events vom Core via definiertem Event-Bus (Callbacks / Swift-Concurrency)
- Hält keinen persistenten Zustand selbst — kein `@State` für Business-Daten, nur UI-lokale Zustände (z. B. Fokus, Scroll-Position)
- Dark Mode, Accessibility, i18n-Strings werden auf dieser Schicht verwaltet

---

### Modul 3 — Global Hotkey / Launcher

**Verantwortlichkeit:** Systemweites Abhören von Tastenkombinationen und Auslösen der korrekten App-Reaktion.

- macOS: CGEventTap mit `kCGEventTapOptionDefault` — erfordert Input Monitoring Permission. Registriert zwei separate Hotkeys: Diktat-Hotkey und Command-Hotkey
- Hotkey-Konfiguration stammt aus dem Settings-Modul, wird zur Laufzeit aktualisiert ohne App-Neustart
- Bei Hotkey-Auslösung: speichert atomisch den aktuell fokussierten Prozess und das fokussierte AX-Element (für spätere Text-Injection) — dies geschieht vor jeder anderen Aktion, um Race Conditions zu vermeiden
- Konflikt-Erkennung: prüft beim Speichern neuer Hotkeys ob Systemkonflikte bestehen (z. B. ⌘Space ist Spotlight); warnt den Nutzer, blockiert nicht
- Fallback bei Input Monitoring Permission fehlt: Polling-basierter Hotkey via CGEventSource (eingeschränkt, nur wenn App im Vordergrund) — Feature-Downgrade klar kommuniziert

---

### Modul 4 — Overlay / Palette Layer

**Verantwortlichkeit:** Darstellung des schwebenden Dictation Indicators und der Command Palette, unabhängig von der aktiven App.

- macOS: NSPanel mit `NSWindowStyleMaskNonactivatingPanel` — Panel übernimmt keinen Fokus, aktive App behält ihren Zustand
- Command Palette: zentriert, oben, Spotlight-Proportionen; Erscheinen unter 100 ms (vorgeladen im Speicher, nicht neu erstellt)
- Dictation Indicator: kleines schwebenes Widget nahe Cursor oder am Bildschirmrand, zeigt Live-Wellenform und Transkriptions-Preview
- Beide Overlays sind Level `NSPopUpMenuWindowLevel` — sie schweben über allen normalen Fenstern
- Escape schließt immer, kein Nebeneffekt
- Tastatur-Navigation vollständig: Tab, Arrow Keys, Enter, Escape — keine Maus-Notwendigkeit

---

### Modul 5 — Audio Capture & VAD

**Verantwortlichkeit:** Mikrofon-Zugriff, Audio-Pufferung und Voice Activity Detection — ohne STT-Logik.

- macOS: AVAudioEngine für Low-Latency-Capture, CoreAudio für direkten Buffer-Zugriff falls nötig
- Audio-Buffer liegt ausschließlich im RAM — kein Schreiben auf Disk, kein Persistieren zwischen Sessions
- VAD (Voice Activity Detection): Energie-basiert als primäre Methode (schnell, lokal, kein Modell nötig); optionale Erweiterung mit Silero VAD (kleines ONNX-Modell, on-device) für bessere Genauigkeit in Hintergrundgeräusch-Szenarien
- Konfigurierbare Parameter: Silence-Threshold (ms bis Auto-Stop), Noise-Gate-Level
- Audio-Format: 16 kHz, 16-bit PCM Mono — Standardformat für alle STT-Backends, kein Re-Encoding nötig
- Mikrofon-Status ist ein expliziter Zustand (idle / listening / error) — jede Zustandsänderung wird als Event an UI und Core propagiert
- Bei Audio-Capture-Fehler (z. B. Mikrofon durch andere App blockiert): sofortiger Fehler-Event, kein stiller Retry

---

### Modul 6 — STT Layer (Hybrid)

**Verantwortlichkeit:** Umwandlung von Audio-Buffern in transkribierten Text. Abstraktion über Provider hinweg.

**Interface-Definition (durch Core):** Nimmt Audio-Buffer entgegen, gibt strukturiertes Ergebnis zurück (Text, Konfidenz, Sprache). Kein Provider-spezifischer Code im Core.

**Provider-Implementierungen (als Platform Adapters):**

- **Cloud-Primary (MVP-Default):** OpenAI Whisper API (Realtime oder File-Upload). Vorteile: höchste Qualität, multilinguale Unterstützung, kein lokaler Ressourcenverbrauch. Nachteil: Netzwerkabhängigkeit, Datenschutzrisiko für sensible Inhalte, Kosten.
- **On-device Option A:** Apple SFSpeechRecognizer (macOS 10.15+). Vorteile: privacy-freundlich, keine Kosten, funktioniert offline. Nachteil: Qualität schlechter als Whisper, besonders bei Fachvokabular; kein Zugriff auf Rohmodell.
- **On-device Option B (Phase 2):** whisper.cpp lokal via Metal/CoreML. Vorteile: Whisper-Qualität ohne Cloud, vollständig offline. Nachteil: Modell-Download (~150 MB–1,5 GB je Größe), Initialisierungslatenz, Speicherbedarf.

**Routing-Logik (im Core):**
- Sensitive Mode aktiv → on-device erzwungen (SFSpeechRecognizer im MVP, whisper.cpp ab Phase 2)
- Cloud-Modus aktiv → OpenAI Whisper Primary, SFSpeechRecognizer als Fallback bei Netzwerkfehler
- Nutzer-konfigurierbar: immer lokal / immer cloud / auto

**Qualitäts-/Kostenstrategie:**
- Kurze Befehle (< 5 Sekunden): SFSpeechRecognizer als schneller Local-First-Versuch, bei niedrigem Konfidenz-Score Upgrade auf Cloud
- Lange Diktate: direkt Cloud (Qualität wichtiger)
- Latenz-Ziel: unter 300 ms wahrgenommene Latenz für Diktat-Start bis erste Wörter sichtbar (Streaming wo möglich)

---

### Modul 7 — LLM Orchestration

**Verantwortlichkeit:** Intent-Erkennung aus Transkript, Tool-Auswahl, Parameter-Extraktion, Safety Gate, Bestätigungslogik.

**Teilkomponenten:**

- **Intent Classifier:** Nimmt transkribierten Text entgegen. Klassifiziert in Intent-Typ (DICTATE, SET_TIMER, SET_REMINDER, FILE_OP, CREATE_NOTE, UNKNOWN) mit Parametern. Primär via LLM mit strukturiertem Output (JSON-Schema-erzwungen). Fallback: regelbasierter Classifier für die häufigsten Intents (Timer, Notiz) ohne LLM-Abhängigkeit.
- **Provider Abstraction:** Einheitliches Interface für OpenAI, Anthropic, lokale GGUF-Modelle (via llama.cpp in Phase 2), Enterprise-Endpoints. Konfigurierbar je Nutzer. Failover-Kette definierbar (z. B. Primary: OpenAI, Fallback: lokales Modell).
- **Safety Gate:** Jeder erkannte Intent mit potenziell destruktiver Wirkung (Datei löschen, umbenennen, verschieben, ausführen) durchläuft einen Safety-Check vor Übergabe an Tool Runtime. Safety Gate gibt Freigabe, Ablehnung oder Confirmation-Request zurück. Keine Tool-Ausführung ohne Safety-Gate-Freigabe.
- **Confirmation Layer:** Für alle Tool-Aktionen außer trivialen Read-only-Operationen: strukturierte Bestätigung an UI zurückgeben. UI zeigt dem Nutzer lesbare Zusammenfassung. Erst nach expliziter Bestätigung (Enter / Ja) wird Tool Runtime aufgerufen. Timeout: 30 Sekunden ohne Bestätigung → automatischer Abbruch.
- **Context Window Management:** Conversation-History wird auf das Nötigste beschränkt. Kein persistentes Senden von Transcript-Historie über Sessions hinaus. Prompts werden vor dem Senden auf PII geprüft (Redaction-Filter).

---

### Modul 8 — Tool Runtime

**Verantwortlichkeit:** Ausführung lokaler OS-Operationen auf Basis freigegebener Intents. Kein LLM-Zugriff innerhalb dieses Moduls.

**Verfügbare Tools (MVP):**
- `TimerTool`: Registriert lokalen Timer, triggert Notification via Notification Adapter
- `ReminderTool`: Wie Timer, mit optionalem Kalender-Export (benötigt explizite Calendar-Permission)
- `NoteTool`: Erstellt lokale Markdown-Notiz in konfiguriertem Ordner
- `FileMoveOp`: Verschiebt Dateien, prüft Ziel-Existenz, fragt Nutzer bei fehlendem Ordner
- `FileRenameOp`: Umbenennen mit Undo-Eintrag
- `FileCopyOp`: Kopieren, Konflikterkennung
- `CreateDirectoryOp`: Ordner anlegen, rekursiv

**Tools Phase 2:**
- `PdfMergeTool`: Lokal via PDFKit (macOS) oder pdfium
- `MediaConvertTool`: Via ffmpeg (lokal, kein Cloud-Aufruf)

**Tool-Sicherheitsregeln:**
- Jedes Tool hat eine deklarierte Allowlist an erlaubten Pfadbereichen (Standard: User Home)
- Canonical Path Resolution vor jeder Operation — verhindert Symlink- und Path-Traversal-Angriffe
- Destructive Operations (überschreiben, löschen) erfordern immer Confirmation Layer Freigabe — auch wenn Safety Gate bereits bestanden
- Undo-Log: jede reversible Operation schreibt einen Undo-Eintrag in die Session-History (nicht persistent)
- Kein Shell-Passthrough — alle Operationen über typisierte APIs, kein `sh -c`, kein `exec` mit nutzerkontrolliertem String

---

### Modul 9 — Plugin Framework (Phase 2)

**Verantwortlichkeit:** Erweiterbarkeit durch Drittanbieter-Actions ohne Core-Änderungen.

**Grundprinzip:**
- Plugins sind isolierte Prozesse oder WASM-Module — kein direkter Zugriff auf Core-Memory
- Plugin-Manifest deklariert: Name, Version, benötigte Permissions, exponierte Intent-Typen
- Nutzer muss jede Plugin-Permission explizit genehmigen (analog zu macOS Permission-Dialogen)
- Plugin-Kommunikation über definiertes IPC-Protokoll (ähnlich Language Server Protocol) — keine direkte FFI
- Signing-Anforderung: Plugins müssen signiert sein; unsignierte Plugins werden nicht geladen

**Abgrenzung zur Tool Runtime:** Built-in Tools (Modul 8) laufen im Core-Prozess. Plugins laufen immer außerhalb. Keine Ausnahme.

---

### Modul 10 — Data & Settings

**Verantwortlichkeit:** Persistente Datenhaltung für Konfiguration, Session-History und Undo-Log.

- **Speicher-Engine:** SQLite via rusqlite — minimal, embedded, kein separater Server-Prozess
- **Verschlüsselung:** SQLCipher für Datenbank-at-rest-Verschlüsselung. Datenbankschlüssel liegt ausschließlich im OS-Keychain (macOS: Security.framework, nie in der App-Config)
- **Schemas:** `settings` (Key-Value, typisiert), `session_history` (Transcripts + Intents, mit konfigurierbarer Retention), `undo_log` (session-scoped, gelöscht bei App-Start), `timers` (aktive Timer, überlebt App-Neustart)
- **API Keys:** Werden niemals in SQLite gespeichert — ausschließlich Keychain. In der Datenbank steht nur ein Verweis (z. B. `provider: openai`, kein Key-Material).
- **Retention Policy:** Transcript-History standardmäßig 7 Tage, konfigurierbar (0 = kein Speichern). Im Sensitive Mode: Retention 0, kein Schreiben.
- **Migration:** Schema-Änderungen nur via versionierte Migrations-Skripte — kein Ad-hoc ALTER. Migrations laufen beim App-Start vor jeder Nutzung.

---

### Modul 11 — Observability

**Verantwortlichkeit:** Strukturiertes Logging, opt-in Crash Reporting, Performance-Metriken — ohne PII-Leakage.

- **Logging:** Strukturiertes JSON-Format. Felder: `timestamp`, `level`, `module`, `event`, `session_id` (UUID, session-scoped, kein User-Identifier), plus kontextspezifische Felder. Kein PII, keine API-Keys, keine Dateipfade mit Nutzernamen in Produktions-Logs.
- **Log-Rotation:** Lokal, max. 10 MB, rolling. Im Sensitive Mode: kein persistentes Logging, nur in-memory für aktive Session.
- **Redaction Layer:** Alle ausgehenden Log-Einträge durchlaufen einen Redaction-Filter, der bekannte PII-Muster (E-Mail, Name-Patterns, Pfade mit Home-Directory) durch Platzhalter ersetzt.
- **Crash Reporting:** Opt-in bei Onboarding. Sentry oder äquivalent. Crash-Reports werden vor dem Senden lokal redaktiert (Stack Trace bleibt, User-Daten nicht). Im Sensitive Mode: kein Crash Reporting, immer.
- **Performance-Metriken:** Lokale Messung von STT-Latenz, Intent-Erkennungslatenz, Tool-Ausführungsdauer — intern für Qualitätssicherung, nicht an externe Services gesendet außer bei explizitem Debug-Report durch Nutzer.
