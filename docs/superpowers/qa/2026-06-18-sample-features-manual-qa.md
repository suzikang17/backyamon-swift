# Manual QA — Sample Record/Upload, Community Library, Instrument-Voice Samples

**Date:** 2026-06-18
**Why this exists:** SP1/SP2/SP3 are covered by unit + build gates, but the mic, SwiftUI screens, live server upload, and actual audio output can only be verified by hand on a device/simulator with a live connection. Run this before considering the feature shippable.

**Setup:** Build & run the `Backyamon` scheme on a simulator or device with network. Be registered/connected (My Stuff shows "Connected"). Grant permissions when prompted.

---

## SP1 — Record & Upload a sample

- [ ] My Stuff → **＋ Create Sample**. Screen opens.
- [ ] **Record:** tap Record → mic permission prompt appears → grant → record a few seconds → Stop. "Loaded: …" line shows a non-zero duration.
- [ ] **Mic denied fallback:** (fresh install / revoke mic) tap Record → denial message appears and **Import from Files** still works.
- [ ] **Import:** pick an audio file from Files (incl. an **iCloud Drive** file) → loads with a duration. *(Verifies the security-scoped-resource fix.)*
- [ ] Enter a title; choose **Sound effect** + a slot (e.g. `piece-move`) → **Save** → no error → sheet dismisses → the asset appears in My Stuff after reload.
- [ ] Repeat with **Music loop/track** → saves and appears.
- [ ] **Upload-failure path:** turn off network, try Save → a clear "Upload failed" message (no crash, no half-state).
- [ ] Equip the new SFX → trigger that action in a game → you hear your sample. Equip the music → background music uses it.
- [ ] **AVAudioSession restore:** record a sample, then start/return to a game → normal game audio still plays (not stuck silent/route-locked). *(Verifies the session-restore fix.)*

## SP2 — Community Sample Library

- [ ] My Stuff → an owned audio asset → **PUBLISH** → button reflects published state (optimistic), and it survives a reload (no revert).
- [ ] Open **Gallery** → your published sample appears (reload-on-appear: it shows without a manual refresh).
- [ ] **Filter pills** (All / Pieces / SFX / Music) filter instantly.
- [ ] **Search** field narrows by title; a no-match query shows the empty state.
- [ ] **Preview:** tap an SFX row → plays; tap a **music** row → plays inline; tapping another stops the first. *(Music preview is the SP2 addition.)*
- [ ] **USE** a community SFX → label flips to USING + a slot-aware confirmation toast; it's now equipped (verify in game).
- [ ] No **unpublish** button exists (intentionally cut — server has no such event).

## SP3 — Instrument-Voice Samples (requires the dub engine, now on main)

- [ ] My Stuff → entry point → **AssignVoiceView**. Pick an instrument voice (e.g. **Kick**, then **Bass**).
- [ ] Record or import a sound for it; for a **pitched** voice (bass/organ/skank/melodica) set the **Root MIDI** to the note you actually sang/played. Save → uploads → equips.
- [ ] **RiddimPlayView → Generate & Play:** a busy/generating indicator shows (not a frozen UI), then the loop plays. *(Verifies the async-render fix.)*
- [ ] **Pitch correctness (the key fix):** override the **Bass** with a sample recorded at a **non-default** root (set Root MIDI accordingly) → Generate & Play → the bass is **in tune** with the progression, not sharp/flat. *(Verifies root-note repitch.)*
- [ ] Override a **drum** (kick) → plays at native pitch (no repitch artifacts).
- [ ] **Unequip** the voice → Generate & Play → the default bundled voice returns (no stale override). *(Verifies clear-before-apply.)*
- [ ] Swap a second voice while one is already overridden → both apply correctly together.
- [ ] **Preview vs background music:** equip a community **music** track so it's playing, then Generate & Play a riddim → the background music **pauses** and the riddim plays; tap **Stop** or leave the Riddim screen → the background music **resumes** (it was paused, not clobbered). *(Verifies the preview-player separation.)*

## Cross-cutting

- [ ] Force-quit & relaunch → equipped samples/voices persist (prefs survive); a previously downloaded voice loads from cache (no re-download). *(Verifies the stable cache key.)*
- [ ] No console crashes/exceptions during any flow.

---

## Known minor gaps (not blockers; tracked, not yet fixed)
- Bundled dub **samples are placeholders** pending license vetting.

*(Resolved 2026-06-18: the Gallery USE toast is now riddim-voice-aware via `equippedRiddimId(forSlot:)`, and riddim auditions use a separate preview player that pauses/resumes the equipped background music instead of clobbering it.)*
