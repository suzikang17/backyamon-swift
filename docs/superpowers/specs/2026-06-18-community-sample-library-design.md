# SP2 — Community Sample Library (Browse, Preview, Use, Publish) — Design Spec

## Goal

Let players **browse**, **preview**, and **use** other players' published samples in their own
game, and close the one real gap that blocks that loop: today there is no in-app way to
**publish** a privately-created SP1 sample to the community gallery. Almost all of the
"use it" plumbing already exists and works on `main`; SP2 is mostly UX polish plus a single
publish action — not new infrastructure.

SP2 ships three buildable changes, value-ordered:

1. **PUBLISH** action wired onto owned rows in `MyStuffView`, using the already-existing but
   currently-unwired `SocketClient.publishAsset(assetId:)` RPC. Without this the gallery can
   only be populated from the web.
2. **Music inline preview** in `GalleryView` (and the same fix carries to `MyStuffView` if its
   preview reuses the shared view) — reusing the exact SFX preview pattern, since music today
   only renders a static `music.note` icon.
3. **Use clarity**: relabel the gallery action `EQUIP`/`UNEQUIP` → `USE`/`USING`, plus a
   **slot-aware confirmation toast** so "USE" reads as "use this in my game" and a silent SFX
   slot replacement is surfaced.

Search (client-side title filter over the already-fetched array) ships as a small additive
deliverable in deliverable 2/3's view pass.

## Context — how it fits existing asset/gallery + SP1 + the dub engine

**The "use a foreign published sample" loop already works end-to-end on `main`** (verified):

- `GalleryView` already calls `SocketClient.listGallery()` to fetch every published row
  (`AssetModels.swift:127`), and the server already returns rows ordered `desc(createdAt)`.
- `GalleryViewModel.toggleEquip(_:)` (`GalleryView.swift:392`) calls
  `AssetManager.shared.toggleEquip(asset, socket:)`.
- `AssetManager.toggleEquip`/`equipAsset` (`AssetManager.swift:80`/`:89`) write the user's
  prefs (`prefs.sfx[slot] = id` or `prefs.music = id`) to `UserDefaults`
  (`backyamon_asset_prefs_v1`) and call `loadEquippedAssets(socket:)`.
- `loadEquippedAssets` (`AssetManager.swift:149`) indexes `listMyAssets` by id and, for any
  equipped id the user does **not** own, falls back to `findInGallery(id:)`
  (`AssetManager.swift:232`, a full `listGallery()` scan), then routes piece → svg /
  sfx → `SoundManager.loadCustomSFX` / music → `SoundManager.loadCustomMusic`.

So equipping a foreign gallery asset is already a solved path. The **only** wiring gap is the
inverse direction — getting a private SP1 sample *into* the gallery from inside the app.

**SP1 context:** `SampleUpload.swift` maps every captured sample to `.sfx(slot)` or `.music`
via `SampleKind` (`SampleUpload.swift:5-15`). `decodeAsset` (`AssetModels.swift:176`) only
accepts `piece|sfx|music` and **silently drops** any row with an unknown type. The
`MyStuffView` `· PUBLISHED` badge already reads `asset.status` (`MyStuffView.swift:284-285`),
proving the `status` field round-trips.

**Dub engine context:** SP2 has **no** dependency on `feat/dub-music-generator`. The Riddim
engine (InstrumentID/SampleLibrary/RiddimEngine) is SP3 territory and lives only on that
divergent branch (which also deletes SP1 files). SP2 is fully buildable on `main` as-is. Do
**not** pull the dub branch in for SP2.

## Decisions

| # | Question | Decision | Why |
|---|----------|----------|-----|
| 1 | Is a "sample" a new `AssetType`? | **No.** Reuse `.sfx`/`.music`. | `decodeAsset` only supports `piece\|sfx\|music` and drops unknown types; a new type needs a server contract + migration. SP1 already maps captures to sfx/music. YAGNI. |
| 2 | How does a user publish? | Wire existing `publishAsset(assetId:)` to a PUBLISH button on owned rows in `MyStuffView`. | `publishAsset` exists (`AssetModels.swift:148`), emits `publish-asset` `{assetId}`, fully on `emitWithAck` — but no UI calls it. **Verified present** on backend (`apps/server/src/index.ts:1088`). |
| 3 | How does a player use another's sample? | Reuse `AssetManager.shared.toggleEquip` unchanged. | The foreign-equip path (prefs → `findInGallery` → `loadCustomSFX`/`loadCustomMusic`) is already solved and tested. SP2 only relabels the action and adds a toast. |
| 4 | Add music inline preview? | **Yes** — reuse the SFX `togglePreview` pattern verbatim. | `togglePreview` is already type-agnostic about the underlying audio (URLSession.data → transient `AVAudioPlayer`, guarded by `previewingId`); only `preview(for:)` gates music out today. View-layer change only. |
| 5 | **Unpublish?** | **Cut from SP2.** Publish-only ships. | **VERIFIED: `unpublish-asset` does not exist on the backend** (`apps/server/src/index.ts` registers create/list-my/list-gallery/publish/delete/report only; no `unpublish` anywhere). A client emit would hit the 10s `emitWithAck` timeout, not a clean error. The "fall back to delete" idea is destructive + surprising. To remove a published asset, the existing trash/`deleteAsset` path stays as-is. |
| 6 | Client recency sort? | **Cut.** No client sort. | The server already returns `desc(assets.createdAt)` for both `list-gallery` (`index.ts:1076`) and `list-my-assets` (`:1055`). A client re-sort is redundant non-work and risks fighting server order on `createdAt` ties (and `createdAt==0` rows decode to a single tie-break bucket). |
| 7 | Pass `type` to `listGallery` per pill? | **No.** Keep fetching ALL once, filter pills client-side (current behavior). | Per-pill server fetch trades instant client filtering for per-tap network latency + a spinner flash on every pill. The design's own YAGNI stance defers server-side narrowing as future scaling; honor it. |
| 8 | Search/sort/pagination server-side? | Client-side **search only** (title `localizedCaseInsensitiveContains`) over the fetched array. No sort, no pagination. | Cheap, instant, no new RPC. Server-side search/paging is unjustified at current library size; flagged as future scaling. |
| 9 | Where does equipped music start playing? | Leave as-is. SP2 only loads via `AssetManager`. | `loadCustomMusic` does not auto-start (by design). `GameController`/`OnlineGameController` call `loadEquippedAssets(socket:)` on game start (`GameController.swift:37`, `OnlineGameController.swift:61` — these call `loadEquippedAssets`, **not** `playCustomMusic`); they own the `playCustomMusic()` trigger elsewhere. Changing that risks audio regressions and is out of scope. |
| 10 | Improve creator attribution? | Keep `creatorId.prefix(8)`. | Gallery rows return only `creatorId`, not a displayName. Real usernames need a server change or an N+1 profile fetch. Out of scope; polish follow-up. |

## Architecture — files + responsibilities

| File | Action | Responsibility |
|------|--------|----------------|
| `Backyamon/Online/SampleUpload.swift` | modify | Add two **pure helpers** so the new behavior is unit-testable without a network seam (matching the existing `createAssetPayload`/`parseCreateAssetAck` pattern): (a) `publishAssetPayload(assetId:) -> [String: Any]` returning `["assetId": assetId]`; (b) `filterAssets(_:type:search:) -> [Asset]` applying the type filter and a case-insensitive title `contains`, preserving input order (which is already server-sorted newest-first). |
| `Backyamon/Models/AssetModels.swift` | modify | Re-point `SocketClient.publishAsset` to build its payload via `publishAssetPayload(assetId:)` (no behavior change, just sharing the testable helper). **No model/struct change** — `Asset.status` already carries `private\|published\|removed`. **No `unpublishAsset` added** (server event absent). |
| `Backyamon/Audio/AssetManager.swift` | modify | Add one **read-only** helper for slot-aware USE feedback: `equippedSfxId(forSlot:) -> String?` exposing `prefs.sfx[slot]` (currently `prefs` is `private`; reuse the public `equippedSFXIds` dictionary instead — `equippedSFXIds[slot]`). No equip-logic change. |
| `Backyamon/Views/MyStuffView.swift` | modify | In `assetRow`'s action area, add a **PUBLISH** button when `asset.status == .private`, gated to **owned audio rows (sfx/music)**. On tap call `vm.publish(asset)`. Show the existing `· PUBLISHED` badge when `.published`. Add `MyStuffViewModel.publish(_:)` → `client.publishAsset` → **optimistic** status flip (rebuild the array element; `Asset.status` is `let`) then `reload()` to confirm; on RPC error revert + set `errorMessage`, and on a successful ack whose `reload()` shows the status did **not** flip, surface a soft "Publish didn't take effect" message. Keep 44pt touch targets + Theme styling. |
| `Backyamon/Views/GalleryView.swift` | modify | (a) **Music preview:** in `preview(for:)`, render the same play/stop Button for `.music` as `.sfx` (`music.note` becomes the fallback only when `asset.url == nil`). (b) **Search:** add a `TextField` bound to `vm.searchText` above the list; route both pill filter and search through `filterAssets(...)` in `filteredAssets`. (c) **Empty state:** distinguish "no search match" from "empty gallery" using `searchText.isEmpty`. (d) **USE clarity:** relabel `EQUIP/UNEQUIP` → `USE/USING`; on a successful equip show a slot-aware toast — `"Replaced your <slot> sound"` when an SFX slot already held a *different* asset (read via `AssetManager.shared.equippedSFXIds[slot]` **before** equipping), else `"Added to your game"`. (e) **Reload-on-appear:** call `reload()` on re-appear so a just-published asset shows up (cross-view freshness; each view owns its own `SocketClient`). |
| `Backyamon/Views/GalleryView.swift` (VM) | modify | Add `@Published var searchText = ""`; change `filteredAssets` to delegate to `filterAssets(assets, type: filter.assetType, search: searchText)`. Add a transient `toastMessage`/`showToast` state surfaced by the view. |
| `SampleTests/SP2GalleryTests.swift` | create | Unit tests in the **existing `SampleTests` target** (reuse it — `project.yml:55-64` globs `path: SampleTests`). Cover the pure helpers + a USE-label round-trip (see Testing). |
| `project.yml` | none | `SampleTests` already globs `SampleTests/*.swift`; no manifest edit. The only action is running `xcodegen generate` after adding the new test file so Xcode picks it up. |

## Data flow

**PUBLISH (populate the library):**
`MyStuffView` row PUBLISH tap → `MyStuffViewModel.publish(asset)` → optimistically replace the
local row with `status = .published` → `SocketClient.publishAsset(assetId:)` →
`emitWithAck("publish-asset", publishAssetPayload(assetId:))` → server flips
`assets.status private→published` (scoped by `creatorId`) → `reload()` (`listMyAssets`)
confirms. Badge shows `· PUBLISHED`. The row is now returned by `listGallery` for everyone.

**BROWSE:**
`GalleryView.task` → `vm.start()` → `client.connect()`+`register()` → `vm.reload()` →
`client.listGallery()` (no type; ALL once) → `{assets:[...]}` → `decodeAssetList` → `[Asset]`
(already newest-first) → `filteredAssets` = `filterAssets(assets, type:, search:)` → `LazyVStack`.
`reload()` re-runs on re-appear for freshness.

**PREVIEW (sfx AND music):**
row play tap → `vm.togglePreview(asset)` → `URLSession.shared.data(from: URL(asset.url))` on a
detached task → transient `AVAudioPlayer(data:)` → `play()`; `previewingId` guards a single
active preview (existing pattern). Stop on re-tap / `teardown`. Separate from equipped music.

**USE / EQUIP a foreign sample:**
row USE tap → (read `AssetManager.shared.equippedSFXIds[slot]` to detect prior occupant) →
`vm.toggleEquip(asset)` → `AssetManager.shared.toggleEquip(asset, socket:)` → writes prefs →
`loadEquippedAssets(socket:)` → `findInGallery(id:)` resolves the foreign id →
`SoundManager.loadCustomSFX/loadCustomMusic` downloads+caches+overrides → UI shows `USING` +
slot-aware toast (`"Replaced your <slot> sound"` or `"Added to your game"`).

**IN-GAME USAGE (unchanged):**
`GameController.swift:37` / `OnlineGameController.swift:61` call
`AssetManager.loadEquippedAssets(socket:)` on game start; equipped SFX fire on game events;
equipped music starts via `SoundManager.playCustomMusic()` at the controllers' existing trigger.
SP2 does not alter this.

## Error handling

- **Publish RPC error:** `publishAsset` throws `SocketClientError.server` only on an `{error}`
  ack. On any thrown error: revert the optimistic status flip and set `vm.errorMessage`.
- **Publish silent no-op:** server scopes the UPDATE by `creatorId` and returns `{ok:true}`
  even if zero rows matched (`index.ts:1096`). The PUBLISH button is gated to **owned** rows,
  so this is unreachable in normal use; as a guard, after `reload()` if the row's status did
  not become `.published`, surface a soft message rather than leaving a stale optimistic badge.
- **Preview failure:** network/decode errors in the detached preview task clear `previewingId`
  (existing behavior). No crash, no toast.
- **Equip failure:** `loadEquippedAssets` already tolerates a missing/garbled url per asset
  (logs + skips). The USE toast only fires on the happy path.
- **No `unpublish`:** the button does not exist; there is no timeout path to handle. Removing a
  published asset uses the existing trash/`deleteAsset`, which already surfaces errors.

## Testing

All tests in the existing `SampleTests` target (`import XCTest`, `@testable import Backyamon`),
following the `SampleUploadTests` pure-helper style (no live network, hand-built `Asset` rows).

1. `test_publishAssetPayloadShape` — `publishAssetPayload(assetId: "a1")["assetId"] as? String == "a1"`
   and the dict has exactly that key.
2. `test_filterAssets_typeAndSearch` — build sfx/music/piece rows with distinct titles; assert
   `filterAssets(rows, type: .sfx, search: "")` returns only sfx, and
   `filterAssets(rows, type: nil, search: "drum")` returns only title-matching rows
   (case-insensitive).
3. `test_filterAssets_preservesInputOrder` — pass rows already in newest-first order; assert the
   filtered output preserves that order (proves we are **not** re-sorting; honors the
   server's `desc(createdAt)`).
4. `test_filterAssets_searchMissReturnsEmpty` — non-matching search yields `[]` (drives the
   "no search match" empty-state branch).
5. `test_isEquipped_galleryRowSfxRoundTrips` — equip a hand-built foreign sfx gallery row via
   `AssetManager.shared.equipAsset`, then assert `isEquipped(sameRow) == true` (closes the
   USE/USING label risk: a published sfx row must round-trip `decodeSfxMetadata()?.slot`).
   Reset prefs after.

Run command (single sim, by id):
`xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests`

Manual / integration (not unit-tested): the live `publish-asset` RPC, music preview audio,
the USE toast, and reload-on-appear are verified on-device against the backend.

## Out of scope

- **Unpublish** (server `unpublish-asset` event does not exist; would require a cross-repo
  change in `/Users/suki/dev/backyamon/apps/server/src/index.ts`). Removal stays on the
  existing trash/`deleteAsset` path.
- A dedicated `sample` `AssetType` and any server schema/migration for it.
- **Publishing pieces from iOS:** PUBLISH is gated to audio (sfx/music) rows. Pieces are
  publishable server-side via `create-asset`, but SP2's loop is audio; iOS piece publish is a
  deliberate deferral (called out here explicitly).
- Client-side recency sort (server already orders `desc(createdAt)`).
- Per-pill server-side type narrowing (instant client filtering kept).
- Server-side search, sort, or pagination.
- Ratings, comments, favorites, or moderation beyond existing report/delete.
- Real usernames/displayName attribution (`creatorId.prefix(8)` kept).
- SVG piece preview/rendering in the gallery (gold-circle placeholder stays).
- Changing when equipped music starts in-game.
- SP3 instrument-voice binding (different branch, different feature).
- Orphaned-upload cleanup and client-side file-size caps (pre-existing SP1 gaps).

## Open items

- **Backend confirmation (verified, recorded here so it is not re-litigated):**
  `publish-asset` (`index.ts:1088`) and `list-gallery` (`:1067`, `desc(createdAt)` at `:1076`)
  exist and match the iOS contract. `unpublish-asset` is **confirmed absent**.
- **`findInGallery(id:)` scaling:** `loadEquippedAssets` does a full `listGallery()` scan per
  foreign equipped id — on the **game-start path**, not just browse. Fine for a small library;
  with N foreign equips against a growing library this is N full network scans at launch.
  Future: a `get-asset-by-id` RPC or a client cache. Not built in SP2.
- **Preview vs equipped-music contention:** preview uses a transient `AVAudioPlayer`; equipped
  music uses `SoundManager.musicPlayer`. In the Gallery (not in-game) overlap is unlikely; SP2
  ensures preview stops on `onDisappear`/teardown. Stopping already-playing equipped music
  before previewing is not addressed (deemed acceptable outside the game loop).
- **Content safety:** publishing exposes user audio publicly with no client-side content check
  or size cap (pre-existing SP1 gap). Report/delete is the only moderation. Flagged, not solved.
- **Optimistic publish polish:** if a slow socket makes `reload()` lag, the optimistic flip
  covers the badge; revert-on-error keeps it honest.
