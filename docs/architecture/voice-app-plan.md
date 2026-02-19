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
