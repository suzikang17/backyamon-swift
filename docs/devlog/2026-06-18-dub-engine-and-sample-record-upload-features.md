---
lore_type: devlog
created: 2026-06-18
title: "Dub engine + sample record/upload features (SP1–SP3)"
date: 2026-06-18
day: 2
---

**Built a sample-based dub riddim engine and three user-sample sub-projects (record/upload, community library, instrument-voice swaps), drove design/build/review through multi-agent workflows, fixed every finding, and shipped it all green to main.**

## What got done
- Investigated the music-generator idea against the existing all-procedural audio (`MusicEngine`, `SoundManager`, the asset/gallery system). Prototyped sound offline in pure-stdlib Python and confirmed synthesis tops out at "decent"; pivoted to a **hybrid sample** approach with the Teenage Engineering EP-40 Riddim as the north star.
- Shipped the **dub riddim engine** (branch `feat/dub-music-generator`): `Chord`, `repitch`, `RiddimPattern` (swing), `SampleLibrary` (bundled kit), `RiddimEngine` (loop assembly → full-chord voicing → offline `AVAudioUnitDelay`/`Reverb` → WAV render), and `SoundManager` local playback. TDD, later merged to `main`.
- **SP1 — record/upload**: `AudioRecorder` (AAC m4a), `AssetUploader`, `SocketClient.createAsset` (presigned-R2), `CreateSampleView`, My Stuff entry point. Reuses the existing server `create-asset` flow — no backend changes.
- **SP2 — community library**: publish + gallery search/filter + inline music preview + slot-aware USE toast + reload-on-appear; pure helpers `filterAssets`/`publishAssetPayload`.
- **SP3 — instrument-voice samples**: `SampleKind.riddimVoice`, `SampleLibrary` per-voice override (`[InstrumentID: Int?]`), `RiddimEngineHolder`, `RiddimVoiceLoader`, `AssetManager` riddim-slot routing with backward-compatible prefs, `AssignVoiceView` + `RiddimPlayView`. Required merging the dub branch into `main`.
- Ran three **multi-agent workflows**: design+plan SP2/SP3 (explore→design→adversarial critique→write docs), a 27-step sequential TDD build (SP2 → dub merge → SP3), and an independent 5-dimension review with adversarial verification.
- Fixed all confirmed review findings plus the two deferred design items. Final state: **61 tests green** (40 `SampleTests` + 21 `RiddimTests`), manual-QA checklist written, everything pushed to `origin/main`.

## Decisions
- **Hybrid samples over pure synthesis** — proven realism ceiling; modeled every voice as a *swappable slot* so real/licensed samples drop in later with no rearchitecting.
- **Reuse `sfx`/`music` asset types** for user samples now (no server change); a dedicated `sample` type is deferred.
- **Free chord builder with dub-recommended chords** — the user consistently prefers expressive control + smart defaults over foolproof restriction.
- **Engine emits continuous loopable stems; the player performs the arrangement via faders** — don't hand-author linear songs.
- **Riddim audition = transient preview** that pauses/resumes the equipped background music, rather than a second simultaneous player or a destructive clobber.

## Issues
- Offline synthesis prototype: a Schroeder reverb all-pass read+wrote the same buffer, making feedback ≈1.7 → infinity → NaN → "high-pitched garbage." Fixed with separate in/out buffers.
- **The Agent-tool code reviewers no-op'd the entire session** (read the diffs, then returned "Noted."/"Complete." with no verdict). Worked around it with workflow-based reviewers + direct `xcodebuild` verification.
- Review caught SP3's headline bug: the user-chosen **root MIDI note was plumbed end-to-end but `RiddimEngine` never applied it**, so override samples at a non-default root played sharp/flat. Fixed via `defaultRootMidiNote(for:)` delta math.
- Persistent SourceKit "Cannot find type" errors were indexing noise all session — `xcodebuild` was the real gate, not the editor.
- `xcodegen` wasn't on PATH inside workflow agents (used the nix-store binary); the simulator destination needs the **full UDID** (`F277ABC0-BCCF-4D05-BBBE-2EF2C717596E`) because the short prefix is ambiguous (arm64 + x86_64).
- SP3 Task 14 died on a transient "API Error: Overloaded" after editing `MyStuffView` but before its commit; finished by hand.
- Other-session commits (lore/devlog tooling, a landscape-board feature) interleaved on `main` during the build — no conflicts, but the history is braided.

## What to remember
- The backend `create-asset` presigned-R2 upload already exists (web `/create`); iOS only needed the emit + an HTTP PUT — **no server changes** for upload or the community library.
- The dub engine + SP3 are now on `main`. The bundled dub **samples are placeholders pending license vetting** — swap before any public release.
- **Manual QA is still outstanding** (mic/UI/live-upload/audio): `docs/superpowers/qa/2026-06-18-sample-features-manual-qa.md`.
- Specs and plans live under `docs/superpowers/{specs,plans}`; the audio prototypes are in `.superpowers/brainstorm/` (gitignored).

---

## Commits
- 88d9ec0 fix(sp3): riddim audition uses a preview player (pause/resume bg music); gallery toast is riddim-voice-aware
- 3411b61 docs: manual QA checklist for sample record/upload, community library, instrument-voice samples
- b14849b test+chore: cover filterAssets whitespace-trim/prefs-decode gaps; remove dead unequipAsset(assetId:) overload; fix doc
- 2c58728 fix(sp2/sp3): apply review findings — root-note repitch, secure import, stable cache key, async render, stale-override clear, session restore, test hardening
- 09b877f feat(sp3): My Stuff entry points for assign-voice + generate/play
- ed8f4d7 feat(sp3): add RiddimPlayView generate-and-play trigger
- 5ca99df feat(sp3): add AssignVoiceView capture/assign/upload screen
- 88cbca6 feat(sp3): thread per-call contentType through uploadSample
- 151720d feat(sp3): resolve and apply riddim overrides in loadEquippedAssets
- 094789e feat(sp3): route riddim slots away from prefs.sfx in equip path
- f572ec2 feat(sp3): add Prefs.riddim with backward-compatible decode
- e003f50 feat(sp3): add RiddimVoiceLoader (download/convert/override)
- 5393785 feat(sp3): add RiddimEngineHolder owner + render/play trigger
- b27c157 feat(sp3): expose RiddimEngine.sampleLibrary accessor
- 240d5a8 feat(sp3): add SampleLibrary per-voice override seam
- 26176de feat(sp3): add riddimVoice(forSlot:) inverse mapping
- fe944a2 feat(sp3): emit riddim slot + root_midi_note metadata
- 86a88e2 feat(sp3): add SampleKind.riddimVoice mapping to sfx
- 15741bf Merge branch 'feat/dub-music-generator'
- 4546cfa feat(sp2): publish action on owned audio rows in MyStuff
- 957017c feat(sp2): reload gallery on re-appear for cross-view freshness
- c267b31 feat(sp2): USE/USING relabel + slot-aware confirmation toast
- 793dedc feat(sp2): inline music preview in gallery (reuse SFX pattern)
- 2be16ff feat(sp2): gallery search field + no-match empty state
- d8b2723 feat(sp2): GalleryViewModel filteredAssets via filterAssets + searchText
- d6d9bb1 feat(sp2): expose AssetManager.equippedSfxId(forSlot:) for USE toast
- 038643a feat(sp2): add filterAssets pure helper (type + title search)
- c83c21c refactor(sp2): publishAsset uses publishAssetPayload helper
- ab2b44a feat(sp2): add publishAssetPayload pure helper
- ea93ee1 test(sp2): add SP2GalleryTests file to SampleTests target
- c4ddb19 docs: SP2 (community sample library) + SP3 (instrument-voice samples) design specs & plans
- ff69fc4 Merge: user sample record & upload (SP1)
- ee44933 build: regenerate Info.plist with mic usage description
