# grurder

A generative MIDI sequencer for [monome norns](https://monome.org/docs/norns/). Takes input from [8mu](https://www.musicthing.co.uk/8mu_page/) and outputs two evolving melodic voices to [mmMidi](https://busycircuits.com/pages/alm023) for eurorack.

## Hardware

- **norns** (or norns shield)
- **8mu** — 8-fader MIDI controller by Music Thing Modular (optional but recommended)
- **mmMidi** — MIDI-to-CV module by ALM/Busy Circuits (or any MIDI-capable voice)

## Install

From the norns maiden REPL:

```
;install https://github.com/icco/grurder
```

## How It Works

grurder generates two complementary melodic sequences using a combination of Euclidean rhythms and a shift-register pitch generator. The 8mu's faders shape the generative parameters in real time.

### Euclidean Rhythms

The rhythm for each voice is generated using the Björklund algorithm, which distributes a given number of pulses as evenly as possible across a number of steps. This produces patterns found across many musical traditions — for example, 5 pulses across 8 steps yields a pattern common in West African music.

Voice 1 uses the fader-controlled step count, pulse count, and rotation directly. Voice 2 automatically uses the complementary pattern (it fills the gaps left by voice 1) with an offset rotation, creating interlocking rhythms.

Reference: Godfried Toussaint, "The Euclidean Algorithm Generates Traditional Musical Rhythms" (2005). Proceedings of BRIDGES: Mathematical Connections in Art, Music, and Science.

### Turing Machine Pitch Generation

Pitch is determined by a 16-bit shift register inspired by Tom Whitwell's Turing Machine module. Each active step, the register shifts right by one bit. The bit that wraps around from the bottom to the top can be flipped with a configurable probability:

- **Probability 0**: the register loops perfectly, giving a locked repeating melody
- **Probability 1**: every wrapping bit is randomized, producing fully generative pitch
- **In between**: the melody gradually evolves, drifting away from the original pattern

Each voice has its own independent register but shares the same flip probability, scale, and root note. The register value is mapped to a scale degree and octave to produce the output MIDI note.

Reference: Tom Whitwell / Music Thing Modular, [Turing Machine](https://www.musicthing.co.uk/Turing-Machine/).

### Complementary Counterpoint

Voice 2's rhythm is the complement of voice 1 — if voice 1 has 5 pulses in 8 steps, voice 2 has 3 pulses in 8 steps, offset by half the step length. This means when voice 1 is dense, voice 2 is sparse, and vice versa. Combined with independent pitch registers, this creates a natural two-voice counterpoint.

## 8mu Fader Mapping

The 8mu's faders (CC 34–41) map to:

| Fader | CC | Parameter | Range |
|-------|-----|-----------|-------|
| 1 | 34 | Step count | 4–16 |
| 2 | 35 | Pulse count | 1–steps |
| 3 | 36 | Rotation | 0–steps-1 |
| 4 | 37 | Flip probability | 0 (locked) – 1 (random) |
| 5 | 38 | Scale | major, minor, pentatonic, dorian, phrygian, lydian, mixolydian |
| 6 | 39 | Root note | C through B |
| 7 | 40 | Octave range | 1–4 |
| 8 | 41 | Tempo | 40–240 BPM |

## 8mu Button Mapping

| Button | Note | Action |
|--------|------|--------|
| A | C2 | Reset both sequences |
| B | C3 | Randomize pitch registers |
| C | C4 | Toggle voice 2 mute |
| D | C5 | Cycle scale |

## Norns Controls

The script is fully usable without 8mu via the norns hardware:

- **E1**: Tempo
- **E2**: Flip probability
- **E3**: Root note
- **K1**: Toggle between sequence view and fader view
- **K2**: Reset sequences
- **K3**: Randomize pitch registers

## Screens

**Sequence view** (default): Shows both voices as horizontal step displays. Each column represents a recent step — height indicates pitch, brightness indicates recency. The current step is brightest. Dots along the bottom show the active Euclidean pattern. Header displays root note, scale, and tempo.

**Fader view**: Shows the current 8mu CC values as eight vertical bars with parameter labels.

## MIDI Output

- Voice 1 sends on MIDI channel 1
- Voice 2 sends on MIDI channel 2
- Velocity is fixed at 100 (suitable for gate-based eurorack setups)
- MIDI device ports are configurable in the norns params menu

## References & Further Reading

- Godfried Toussaint, ["The Euclidean Algorithm Generates Traditional Musical Rhythms"](https://cgm.cs.mcgill.ca/~godfried/publications/banff.pdf) (2005)
- Tom Whitwell, [Turing Machine](https://www.musicthing.co.uk/Turing-Machine/) — Music Thing Modular
- [Music Thing Modular reading list](https://www.musicthing.co.uk/books.html) — books on electronic music, generative systems, and instrument design
- [norns scripting reference](https://monome.org/docs/norns/scripting/)
- [Algorithmic composition](https://en.wikipedia.org/wiki/Algorithmic_composition) — Wikipedia

## License

MIT
