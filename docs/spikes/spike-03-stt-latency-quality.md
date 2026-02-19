# Spike 03 — STT Latenz und Qualität (macOS)

Status: Vorbereitet  
Datum: 2026-02-19  
Owner: Syntic Core Team

## Ziel

Bewerten, ob STT für den Command- und Dictation-Flow schnell und zuverlässig genug ist.

## Leitfragen

- Ist die wahrgenommene Latenz bis zum ersten sichtbaren Text niedrig genug?
- Wie unterscheiden sich lokale und Cloud-Provider bei kurzen und längeren Inputs?
- Ab welchem Punkt ist Fallback/Provider-Switch sinnvoll?

## Testdesign

### Provider

- `sfspeech` (lokal)
- `openai-whisper` (cloud)

### Input-Längen

- 2s
- 5s
- 10s

### Sprache

- `de-DE`
- `en-US`

### Geräuschumgebung

- `quiet`
- `noise`

## Metriken

- `first_text_latency_ms`: Hotkey/Start bis erstes sichtbares Token
- `final_text_latency_ms`: Ende Sprechen bis finales Ergebnis
- `subjective_quality`: 1-5
- `notes`: Auffälligkeiten (fehlende Wörter, Halluzinationen, Satzzeichen)

## Ergebnis-Matrix

| Timestamp | Provider | Input seconds | Locale | Noise | First text latency (ms) | Final latency (ms) | Subjective quality (1-5) | Notes |
|---|---|---|---|---|---|---|---|---|
| TBD | sfspeech | 2 | de-DE | quiet | TBD | TBD | TBD | |
| TBD | openai-whisper | 2 | de-DE | quiet | TBD | TBD | TBD | |

## Erfassungs-Skript

```bash
cd /Users/carstenrheidt/Syntic
./scripts/spikes/spike-03-log-measurement.sh \
  --provider sfspeech \
  --seconds 2 \
  --locale de-DE \
  --noise quiet \
  --first-latency-ms 180 \
  --final-latency-ms 430 \
  --quality 4 \
  --notes "stable, one punctuation miss" \
  --append docs/spikes/spike-03-stt-latency-quality.md
```

## Entscheidungsregeln

- Wenn `first_text_latency_ms` regelmäßig > 300 ms bei kurzen Inputs: lokale Priorisierung für Commands prüfen.
- Wenn Cloud klar bessere Qualität liefert, aber Latenz zu hoch ist: hybrid routing (kurz lokal, lang cloud).
- Wenn Qualitätsabweichung bei Fachbegriffen stark ist: provider-spezifische Routing-Regel pro Modus definieren.

## Offene Punkte

- Wann genau wird der Startzeitpunkt gemessen (Hotkey down vs. Audio stream start)?
- Brauchen wir getrennte Metrik für Netzwerklatenz?
