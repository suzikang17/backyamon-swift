# User Sample Recording & Upload — Design

**Date:** 2026-06-14
**Status:** Approved design (Sub-project 1), ready for implementation plan
**Context:** Players want to **record/import their own audio samples, upload them (synced to their account), and build a community library of each other's samples** — usable for instrument voices, game SFX, and background music.

## 1. Goal & overall decomposition

The full feature is several subsystems. It decomposes into three sub-projects, each its own spec → plan → build:

- **SP1 — Record + Upload + My Stuff sync** *(this spec; fully unblocked).* Capture audio on-device (record or import), upload it to the user's account via the existing server `create-asset` flow, and have it appear in **My Stuff**, equippable like web-created assets.
- **SP2 — Community sample library.** Browse / preview / use other players' *published* samples (builds on `list-gallery` + `publish-asset`).
- **SP3 — Instrument-voice samples.** Let a recorded sample back a riddim-engine voice (kick/bass/organ…), connecting to the Phase 1 dub engine.

This document specifies **SP1 only**.

## 2. Key finding: the backend already supports upload (no server changes)

The server (`apps/server`, separate repo) already implements a presigned-R2 upload flow used by the web `/create` page. iOS only reads assets today; SP1 adds the iOS *create* path against the **existing** contract:

1. Emit `create-asset { type, title, metadata, needsUpload: true, contentType, fileSize }` → server replies `{ id, uploadUrl }` (a presigned R2 PUT URL; the row is created as `status: "private"`, owned by the guest).
2. HTTP **PUT** the audio bytes to `uploadUrl` with the matching `Content-Type`.
3. The asset now returns from `list-my-assets` with a public `url`; `publish-asset` later moves it into `list-gallery` (SP2).

Server `type` is restricted to `piece | sfx | music`. **Decision: reuse existing types now, migrate to a dedicated `sample` type later.** SP1 stores:
- one-shot samples as **`sfx`** (`SfxMetadata { slot, duration_ms, file_size }`)
- loops/tracks as **`music`** (`MusicMetadata { duration_ms, file_size }`)

## 3. Capture

Two capture paths (**decision: support both**):
- **Record** via `AVAudioRecorder` to a temporary **`.m4a` (AAC)** file (compact; plays via `AVAudioPlayer` and from the public URL). Requires mic permission.
- **Import** an existing audio file via SwiftUI `.fileImporter`; copy into a temp file. (No mic permission needed.)

Recording settings: AAC, 44.1 kHz, mono, a modest bitrate; `Content-Type: audio/mp4` on upload. Keep durations short (one-shots a few seconds; loops modest) to stay within upload size limits.

## 4. Architecture (new units, each one responsibility)

- **`AudioRecorder`** (`Backyamon/Audio/Capture/AudioRecorder.swift`) — wraps `AVAudioRecorder`. Requests mic permission; `start()` / `stop() -> URL`; exposes `isRecording` and recorded `duration`. Records to a temp `.m4a`.
- **`AudioImporter`** (SwiftUI `.fileImporter` integration, inside `CreateSampleView`) — picks an audio file, copies it to a temp URL, reads its duration via `AVAudioFile`/`AVURLAsset`.
- **`SocketClient.createAsset(...)`** (extend `Backyamon/Models/AssetModels.swift` `SocketClient` extension) — `func createAsset(type: AssetType, title: String, metadata: String, contentType: String, fileSize: Int) async throws -> (id: String, uploadUrl: String?)`. Emits `create-asset` with ack; decodes `{id, uploadUrl}`; throws `SocketClientError.server` on `{error}`. Mirrors existing `listMyAssets`/`deleteAsset` RPCs.
- **`AssetUploader`** (`Backyamon/Online/AssetUploader.swift`) — orchestrates one upload: builds metadata JSON, calls `createAsset`, then `URLSession` PUT (`httpMethod = "PUT"`, `Content-Type` header) of the file `Data` to `uploadUrl`. Returns the new asset `id` on success; surfaces errors.
- **`CreateSampleView`** (`Backyamon/Views/CreateSampleView.swift`) — the capture/name/type screen and its small view-model: record/import controls, preview playback, a title field, a type picker (Sound effect → slot picker, or Music), and a Save button that drives `AssetUploader` and dismisses on success.

**Entry point:** `MyStuffView` gains a **＋ Create Sample** action (header button and/or the empty-state CTA), replacing the stale "create on the web" empty-state text. On successful save it calls the existing `MyStuffViewModel.reload()`.

## 5. Data flow

```
record/import → temp .m4a (+ duration, fileSize)
   → user enters title, picks type (sfx+slot | music)
   → build metadata JSON (SfxMetadata | MusicMetadata)
   → SocketClient.createAsset(...) → {id, uploadUrl}
   → URLSession PUT bytes to uploadUrl (Content-Type: audio/mp4)
   → MyStuffViewModel.reload() (list-my-assets) → asset appears with public url
   → existing AssetManager.equipAsset(...) equips it (SFX slot / music)
```

## 6. Error handling & permissions

- Add `NSMicrophoneUsageDescription` to `project.yml` `info.properties` (regenerate project).
- Mic permission denied → disable record, keep import available, show a one-line explanation.
- `create-asset` returns `{error}` → surface message, stay on screen (no orphan upload).
- PUT failure (network / non-2xx) → surface, offer retry; the private asset row exists server-side but without bytes — a retry can re-PUT to a fresh `create-asset` (acceptable for SP1; orphan cleanup is out of scope).
- Save disabled until there's a recorded/imported file and a non-empty title.

## 7. Testing

Unit-test the deterministic pieces (in `RiddimTests` or a new `CaptureTests` target):
- Metadata JSON construction for `sfx` (slot/duration_ms/file_size) and `music` round-trips via the existing `decodeSfxMetadata()` / `decodeMusicMetadata()`.
- `create-asset` payload dictionary shape (type/title/metadata/needsUpload/contentType/fileSize).
- `AssetUploader` builds a `PUT` `URLRequest` with the correct `Content-Type` and body (inject a `URLSession`/protocol seam so no real network is hit).

Mic recording and live upload are verified manually/integration (hardware + network), not unit-tested.

## 8. Out of scope (SP1)

- Browsing/using *other* users' samples (SP2).
- Backing riddim-engine instrument voices with samples (SP3).
- Waveform trimming/editing, normalization, or effects on capture.
- A dedicated server `sample` type / any backend change.
- Orphaned-upload (created row, failed PUT) server cleanup.

## 9. Open items for the plan

- Confirm the exact ack envelope keys from the server (`id`, `uploadUrl`) and `SocketClientError` mapping.
- Confirm any server-side `fileSize` ceiling for the presigned PUT; pick sensible client caps.
- Whether to add a separate `CaptureTests` target or reuse `RiddimTests`.
