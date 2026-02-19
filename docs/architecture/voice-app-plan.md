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
