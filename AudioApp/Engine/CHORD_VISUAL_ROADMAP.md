# Chord & Musical Character → Visual Effects Roadmap

## Overview

Extend the audio-reactive system so that **musical interpretation is decoupled from visual presentation**. The same `MusicalContext` drives lights now and particle systems later. Consumers (light mapper, particle mapper) only read the context; they contain no chord or audio logic.

---

## Phase 1: Interpretation Layer Only

### Goal

Add `MusicalContext` and a `MusicalInterpreter` that **extends** the existing `AudioAnalyzer` output — including pitch (MPM), bands, spectrum, and RMS. The interpreter sits on top of what we already have; it does not replace pitch analysis.

### Compute

| Output     | Source                                                                 |
|-----------|------------------------------------------------------------------------|
| **energy** | RMS / rolling average                                                  |
| **brightness** | Spectral centroid, or band ratio (treble / total)                     |
| **melancholy** | Major/minor heuristic **using pitch + spectrum** when pitch confidence is high; else fallback to brightness + energy |
| **dominantPitch** | From `getDetectedPitch()` — exposed for hue mapping in light mapper   |
| **pitchConfidence** | From `getPitchConfidence()` — gates when pitch-based features are valid |

### Major/Minor Heuristic (with pitch)

When `pitchConfidence` is above threshold:

- Get spectrum magnitudes and sample rate from `AudioAnalyzer`.
- Compare energy at minor third (`pitch * 2^(3/12)`) vs major third (`pitch * 2^(4/12)`). Map these frequencies to FFT bins, sum magnitude in a small window around each.
- More energy at minor third → bias melancholy higher (sadder). More at major third → bias lower (happier).
- Blend with `brightness` and `energy` for stability.

When confidence is low: `melancholy = f(brightness, energy)` only (e.g. dark + quiet → high melancholy).

### MusicalContext (Phase 1)

```text
energy, brightness, melancholy,
dominantPitch, pitchConfidence   // for hue mapping when confident
```

Interpretation layer owns all logic. Output: `MusicalContext` struct.

---

## Phase 2: Chord Support

### Goal

Introduce chord-level information into `MusicalContext` using simple rules.

### Add

- **Pitch-class profile (chroma)** — 12-bin representation of which pitch classes (C, C#, D, …) have energy. Built from FFT/spectrum.
- **chordRoot** — Inferred root note from chroma.
- **quality** — Coarse: major / minor / diminished (simple rules from chroma peaks).
- **tension** — From dissonance or chord quality.
- **stability** — From consonance, resolution, or simple heuristics.

### Technical Notes

- Chroma: map each FFT bin to a pitch class, accumulate magnitude. Normalize.
- Chord root/quality: template matching against major/minor/dim triads, or peak-picking from chroma.
- Tension/stability: rule-based (e.g., diminished → high tension; major triad → low).

---

## Phase 3: Visual Consumers

### Goal

Map `MusicalContext` to visual parameters. Same context, different consumers.

### Light Mapper

Map `MusicalContext` → **hue**, **saturation**, **intensity**.

- Hue from chord root, mood, or energy
- Saturation from tension, energy
- Intensity from brightness, energy

### Particle Mapper

Map same `MusicalContext` → **forces**, **spawn rate**, **size**, **colors**.

- Forces from energy, tension
- Spawn rate from energy
- Size from brightness, energy
- Colors from chord root, melancholy, brightness

---

## Architecture

```
[Audio] → [AudioAnalyzer] → [MusicalInterpreter] → MusicalContext
                                                          ↓
                              ┌───────────────────────────┴───────────────────────────┐
                              ↓                                                       ↓
                        [Light Mapper]                                         [Particle Mapper]
                              ↓                                                       ↓
                    hue, saturation, intensity                            forces, spawn, size, colors
```

- **MusicalInterpreter** — Reads pitch (MPM), bands, spectrum, RMS from AudioAnalyzer. Produces energy, brightness, melancholy, dominantPitch, pitchConfidence (Phase 1); chroma, chordRoot, quality, tension, stability (Phase 2). Outputs `MusicalContext`.
- **Mappers** — Pure translation: `MusicalContext` → domain params. No audio, chord, or spectrum logic.
