# Dub Music Generator — Design

**Date:** 2026-06-13
**Status:** Approved design, ready for Phase 1 implementation plan
**North star:** Teenage Engineering **EP-40 Riddim** — instant, authentic, foolproof-but-deep reggae/dub creation.

## 1. Goal

Let a player quickly and easily create a Jamaican (reggae/dub) beat inside the
Backyamon iOS app and use it as background music. It must sound like reggae/dub
**immediately** and stay foolproof, while giving real, expressive control.

### Why now / what exists
- `Backyamon/Audio/MusicEngine.swift` already generates reactive in-game reggae
  via pure oscillator synthesis (3 styles, 4 mood crossfades, 4 stems). It is
  **reactive game scoring**, not a creator, and its synthesis is too thin/dry to
  feel "great."
- `Backyamon/Audio/SoundManager.swift` can load + loop a custom music track
  (`loadCustomMusic(url:)` / `playCustomMusic()`).
- The asset system (`AssetManager`, `MyStuffView`, `GalleryView`) lets players
  equip custom `music`/`sfx`/`piece` assets, but **creation currently lives on
  the web** ("Create assets on the web at backyamon.com/create").

This feature brings music **creation into the app**.

## 2. Validated findings (from audio prototyping)

We prototyped the sound offline (pure-stdlib Python ports of the engine DSP,
rendered to audio for listening — see `.superpowers/brainstorm/gen_*.py`). What
we learned, in order:

1. **Pure synthesis hits a ceiling.** Layering, dub FX, and a melodica lead got
   it from "beepy" to "decent," but synthesized drums/bass never read as "great."
2. **Hybrid (real samples) is the jump.** Real recorded one-shots (we used the
   free TidalCycles **Dirt-Samples** for the proof) made the drums and bass
   immediately convincing. **Decision: sample-based voices, synthesis as
   fallback.**
3. **Bass is the most important voice** (dub leads with bass). A deep, round,
   sustained bass sample repitched low + low-passed + shaped sits in the pocket;
   a plinky synth bass does not.
4. **Arrangement is performed, not composed.** With faders, the engine should
   produce **continuous loopable stems**; the player creates dub movement
   (drop-ins, breakdowns, throws) live. Do **not** hand-author linear songs.
5. **Dub production is essential:** spring reverb (esp. on the rim/snare),
   Roland-Space-Echo-style tape delay with wow + feedback throws, tape-warmth
   master, generous space.

## 3. User-facing model (the EP-40 mapping)

- **4 parts:** Drums · Bass · Melodic (organ / guitar skank / melodica) · SFX
  (dub sirens, echo throws).
- **Preset riddims** ("One Drop", "Steppers", "Rockers", "Dub", "Dancehall…"):
  the creator opens on one already grooving → instant authenticity.
- **The player shapes, never starts from blank.**

### Design preference (important)
The player consistently prefers **expressive control over foolproof
simplicity**. Concretely they chose: a stem-mixer + step-grid creator (not a
one-tap vibe picker), and a **free** chord builder (any root + quality) — but
with **dub-correct chord recommendations** surfaced by default.

## 4. Chord model

Free chord builder: per-bar **root + quality** (maj / min / 7 / etc.). Voices
follow the chord automatically — **bass = root**, **organ + skank = full chord
voicing** (root–third–fifth, +7th where chosen). Progression length is
extendable (4 → 8 → …).

**Dub-correct recommendations** (relative to the chosen key; shown in A minor):

| Chord | Role | Note |
|---|---|---|
| Am (i) | tonic | foundation |
| G (♭VII) | subtonic | the roots neighbour chord |
| F (♭VI) | submediant | descending roots flavour |
| Dm (iv) | minor subdominant | steppers/one-drop staple |
| Em (v) | minor dominant | softer than major V |
| C (♭III) | relative major | a lift without leaving the mood |
| E7 (V7) | dominant | optional tension, sparingly |

Idiomatic preset vamps: **Am–G**, **Am–G–F–G**, **Am–Dm**, **Am–F–G**. The
builder highlights the recommended chords and ghosts the rest; any chord remains
selectable.

## 5. Architecture

### Phase 1 — Sound engine (foundational; build first)

A new subsystem (proposed `Backyamon/Audio/Riddim/`), kept separate from the
reactive `MusicEngine` but sharing low-level voice primitives. It could later
also power the in-game reactive music.

- **Voice = swappable slot.** A voice plays either a bundled sample one-shot
  (default) or a synth recipe (fallback). This is the "real-ready" architecture:
  swapping in better/licensed samples later requires no rearchitecting.
  - Voices: kick, snare/rim, closed/open hat, shaker, conga/perc, bass,
    organ, guitar skank, melodica, dub siren.
  - Sample playback supports **repitching** (linear-interpolation resample) so
    bass/organ/skank/melodica follow chords; drums play at native pitch.
- **4 stems** (Drums, Bass, Melodic, SFX), each a mixer node with its own
  fader + mute, summed to a master.
- **Sequencer:** per-instrument step grid over the bar count; one-drop +
  swing built into preset patterns. Stems loop continuously.
- **Chord engine:** maps the progression to per-bar voicings for bass/melodic
  voices.
- **Dub FX bus:** per-stem sends to (a) spring **reverb**, (b) **tape/space
  echo** (modulated delay with wow + feedback), and a master **tape-warmth**
  chain (gentle high-cut + glue saturation). Punch-in FX (siren, echo throw,
  filter sweep) are momentary triggers.
- **Format:** 44.1 kHz, stereo.
- **Offline render:** render the current loop (N bars, looped to a chosen
  length) to an audio file via AVAudioEngine manual/offline rendering, for
  saving + equipping.

Implementation note: the prototype DSP in `.superpowers/brainstorm/gen_hybrid.py`
(sample load, repitch, bass shaping, space-echo, Schroeder reverb, master) is the
reference for the Swift port. AVFoundation provides native nodes for much of the
FX (`AVAudioUnitReverb`, `AVAudioUnitDelay`), preferable to hand-rolled DSP where
they fit.

### Phase 2 — Creator UI (EP-40-style; follow-on spec)

- **Stem mixer:** per-stem fader + mute for the 4 parts.
- **Step grid:** per-instrument rows, tap to toggle hits, pre-seeded from the
  preset riddim.
- **Chord-progression editor:** free per-bar root+quality with dub recs;
  extendable bars; loops live as edited.
- **Punch-in FX:** momentary siren / echo-throw / filter-sweep controls.
- **Transport:** play/stop, tempo, swing, key.
- **Preset riddims** as starting points.
- **Save:** render → save as a `music` `Asset` → equip as background music.
- **Aesthetic:** existing gold/green/cream `Theme` (already EP-40-aligned:
  orange/cream/dark-green).

### Integration points
- **Output → equip:** rendered file feeds `SoundManager` custom-music playback
  (extend `loadCustomMusic` to accept a local file URL) and is registered as an
  `Asset` via `AssetManager` so it appears in **My Stuff** and can be equipped /
  published — bringing creation in-app alongside the existing web flow.
- **Reactive music:** out of scope for this feature; the new engine may later
  replace `MusicEngine`'s synthesis, but that is not required here.

## 6. Sample sourcing / licensing
- Prototype used **TidalCycles Dirt-Samples** (free, sampling-friendly) for
  proof only.
- For shipping: vet licenses — use CC0 sources (e.g. Clean-Samples) or a
  licensed royalty-free reggae/dub pack. Bundle a small curated kit (a handful
  of short one-shots per voice; total well under a few MB).

## 7. Scope / decomposition
- **Phase 1 (this spec → plan):** the sample-based stem engine + chord voicing +
  dub FX + offline render. Verifiable by rendering a great-sounding hybrid dub
  loop in-app and equipping it.
- **Phase 2 (separate spec):** the creator UI and asset/equip integration.
- **Non-goals:** replacing the reactive in-game `MusicEngine`; web parity for
  creation; vocal recording (EP-2350 "Ting" equivalent); MIDI/export.

## 8. Open items for the plan
- Final curated sample kit + licensing choice.
- Whether to hand-roll FX DSP (matches prototype exactly) or use AVFoundation FX
  units (less code) — likely a mix.
- Bundle-size budget for samples.
- Loop seam handling for offline render (tail wrap / crossfade).
