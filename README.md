# grurder

A generative MIDI sequencer for [monome norns](https://monome.org/docs/norns/). Takes input from an [8mu](https://www.musicthing.co.uk/8mu_page/) and outputs two evolving melodic voices to eurorack via [mmMidi](https://busycircuits.com/pages/alm023) (or any MIDI-capable module).

## Hardware

- **norns** (or norns shield)
- **8mu** — 8-fader MIDI controller with accelerometer (optional but recommended)
- **mmMidi** or any MIDI-to-CV module

## Install

```
;install https://github.com/icco/grurder
```

## What it does

Two independent voices, each with their own rhythm and melody generation. Rhythms come from Euclidean patterns[^1] — distribute some pulses across some steps and you get patterns that show up all over world music. Pitch comes from a shift register inspired by the Turing Machine[^2] — a 16-bit loop that drifts based on a probability knob:

- **Prob 0**: locked repeating melody
- **Prob 1**: fully random
- **In between**: gradual drift

Both voices share scale, root, and octave range but have independent registers and patterns.

## 8mu mapping

### Faders (CC 34–41)

| Fader | Sequence | Parameter | Range |
|-------|----------|-----------|-------|
| 1 | Seq 1 | Step count | 4–16 |
| 2 | Seq 1 | Pulse count | 1–steps |
| 3 | Seq 1 | Rotation | 0–steps-1 |
| 4 | Seq 1 | Flip probability | 0–1 |
| 5 | Seq 2 | Step count | 4–16 |
| 6 | Seq 2 | Pulse count | 1–steps |
| 7 | Seq 2 | Rotation | 0–steps-1 |
| 8 | Seq 2 | Flip probability | 0–1 |

### Tilt (accelerometer)

The 8mu's accelerometer controls MIDI velocity for each voice. Configure your 8mu to send tilt on CC 14 (X-axis → seq 1 velocity) and CC 15 (Y-axis → seq 2 velocity) via the [8mu web editor](https://tomwhitwell.github.io/Smith-Kakehashi/). Tilt maps to a velocity range of 30–127. Without tilt input, velocity defaults to 100.

### Buttons

| Button | Action |
|--------|--------|
| A (C2) | Reset both sequences |
| B (C3) | Randomize pitch registers |
| C (C4) | Toggle seq 1 mute |
| D (C5) | Toggle seq 2 mute |

## Norns controls

Works fine without an 8mu:

- **E1**: Tempo
- **E2**: Octave range (1–4)
- **E3**: Root note
- **K2**: Toggle sequence view / fader view
- **K3** short: Reset sequences
- **K3** long: Randomize pitch registers

## Screens

**Sequence view** (default): Two lanes showing recent note history. Height = pitch, brightness and bar size = velocity, with the current step brightest. Dots along the bottom show the Euclidean pattern. Header shows root, scale, tempo, octave range, and current velocity for each voice.

**Fader view**: Eight vertical bars showing the 8mu CC values (stp/pls/rot/prb per sequence), plus velocity readouts and horizontal tilt bars at the bottom.

## MIDI output

- Voice 1 → MIDI channel 1
- Voice 2 → MIDI channel 2
- Velocity controlled by 8mu tilt (defaults to 100 if no tilt input)

### Params menu

- **midi in** — input device (default port 1)
- **midi out** — output device (default port 2)
- **scale** — major, minor, major pent, minor pent, dorian, phrygian, lydian, mixolydian

## License

MIT

[^1]: Godfried Toussaint, ["The Euclidean Algorithm Generates Traditional Musical Rhythms"](https://cgm.cs.mcgill.ca/~godfried/publications/banff.pdf) (2005)
[^2]: Tom Whitwell / Music Thing Modular, [Turing Machine](https://www.musicthing.co.uk/Turing-Machine/)
