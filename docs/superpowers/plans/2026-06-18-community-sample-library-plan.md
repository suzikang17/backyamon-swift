# Community Sample Library (SP2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is independently committable; write the failing test first, watch it fail, then implement.

**Prerequisite branch:** None. SP2 builds on `main` and has **no** dependency on
`feat/dub-music-generator` (that branch is SP3 / the Riddim engine and even deletes SP1 files).
Do **not** branch from or merge in `feat/dub-music-generator`. Create a fresh feature branch off
`main` (e.g. `feat/community-sample-library`).

**Goal:** Let players browse, preview, and use other players' published samples, and add the one
missing piece that unblocks the loop — an in-app PUBLISH action that pushes a private SP1 sample
to the community gallery via the existing `publish-asset` RPC. Also: music inline preview, a
client-side title search, a "no search match" empty state, and a slot-aware USE confirmation toast.

**Architecture:** Reuse existing infrastructure end-to-end. Two new **pure helpers** in
`SampleUpload.swift` (`publishAssetPayload`, `filterAssets`) make the new behavior unit-testable
behind the same pure-function seam as `createAssetPayload`. `publishAsset` already exists in
`AssetModels.swift`; the foreign-equip path (`AssetManager.toggleEquip` → `loadEquippedAssets` →
`findInGallery` → `SoundManager.loadCustom*`) is untouched. View changes are in `MyStuffView`
(PUBLISH button) and `GalleryView` (music preview, search, empty state, USE relabel + toast,
reload-on-appear). **No** `unpublish` (the server event does not exist) and **no** client recency
sort (server already orders `desc(createdAt)`).

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation (`AVAudioPlayer`), URLSession, SocketIO,
XCTest, XcodeGen.

---

## File Structure

**Modified source**
- `Backyamon/Online/SampleUpload.swift` — add pure helpers `publishAssetPayload(assetId:)` and `filterAssets(_:type:search:)`.
- `Backyamon/Models/AssetModels.swift` — re-point `SocketClient.publishAsset` to build its payload via `publishAssetPayload`.
- `Backyamon/Views/MyStuffView.swift` — PUBLISH button on owned audio rows + `MyStuffViewModel.publish(_:)`.
- `Backyamon/Views/GalleryView.swift` — music preview, `searchText`, `filteredAssets` via `filterAssets`, no-match empty state, USE/USING relabel + slot-aware toast, reload-on-appear.

**New tests** (in the **existing** `SampleTests` target — reuse it; do not create a new target)
- `SampleTests/SP2GalleryTests.swift`

**Build manifest**
- `project.yml` — **no edit** (`SampleTests` already globs `path: SampleTests`). Run `xcodegen generate` once after adding the new test file.

**Test target note:** The `SampleTests` unit-test target already exists on `main`
(`project.yml:55-64`, `path: SampleTests`). Reuse it — Task 0 only confirms it builds and is
already wired; no new target is required.

**Standard run command (used in every task):**
```
xcodebuild test -scheme Backyamon \
  -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' \
  -only-testing:SampleTests
```

---

## Task 0: Confirm the existing test target + add the SP2 test file

**Files:** Create `SampleTests/SP2GalleryTests.swift`; run `xcodegen generate`.

The `SampleTests` target already exists and globs `SampleTests/*.swift`. We only add a new file
and regenerate the project so Xcode picks it up. Start with a single smoke test to prove the new
file compiles and runs in the target.

- [ ] **Step 1: Create the test file with one smoke test.**

```swift
// SampleTests/SP2GalleryTests.swift
import XCTest
@testable import Backyamon

final class SP2GalleryTests: XCTestCase {
    /// Smoke: the SP2 test file is wired into the SampleTests target.
    func test_sp2TestFileIsWired() {
        XCTAssertTrue(true)
    }

    // MARK: - Helpers
    private func sfx(_ id: String, title: String, slot: String, createdAt: Int64 = 0) -> Asset {
        let meta = sampleMetadataJSON(kind: .soundEffect(slot: slot), durationMs: 1000, fileSize: 1)
        return Asset(id: id, creatorId: "c", type: .sfx, title: title, status: .published,
                     metadata: meta, r2Key: nil, url: "https://x/\(id)", createdAt: createdAt, updatedAt: createdAt)
    }
    private func music(_ id: String, title: String, createdAt: Int64 = 0) -> Asset {
        let meta = sampleMetadataJSON(kind: .music, durationMs: 1000, fileSize: 1)
        return Asset(id: id, creatorId: "c", type: .music, title: title, status: .published,
                     metadata: meta, r2Key: nil, url: "https://x/\(id)", createdAt: createdAt, updatedAt: createdAt)
    }
    private func piece(_ id: String, title: String) -> Asset {
        Asset(id: id, creatorId: "c", type: .piece, title: title, status: .published,
              metadata: "{}", r2Key: nil, url: nil, createdAt: 0, updatedAt: 0)
    }
}
```

- [ ] **Step 2: Regenerate the project and run.**

```
xcodegen generate
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests
```

**Verify:** `SP2GalleryTests.test_sp2TestFileIsWired` passes; the whole `SampleTests` suite is green.

- [ ] **Step 3: Commit.** `git commit -m "test(sp2): add SP2GalleryTests file to SampleTests target"`

---

## Task 1: Pure helper — `publishAssetPayload(assetId:)`

**Files:** Modify `Backyamon/Online/SampleUpload.swift`; modify `SampleTests/SP2GalleryTests.swift`.

A pure payload helper (mirroring `createAssetPayload`) gives us a testable seam for the publish
RPC without a network stub.

- [ ] **Step 1: Add the failing test.**

```swift
    // Add inside SP2GalleryTests
    func test_publishAssetPayloadShape() {
        let p = publishAssetPayload(assetId: "asset-123")
        XCTAssertEqual(p["assetId"] as? String, "asset-123")
        XCTAssertEqual(p.count, 1)
    }
```

- [ ] **Step 2: Run — expect a compile failure** (`publishAssetPayload` undefined).
```
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests
```

- [ ] **Step 3: Implement the helper** in `SampleUpload.swift` (append after `makeUploadRequest`):

```swift
/// Payload dict for the server `publish-asset` event. Mirrors the inline
/// payload `SocketClient.publishAsset` builds, extracted so it is unit-testable.
func publishAssetPayload(assetId: String) -> [String: Any] {
    return ["assetId": assetId]
}
```

- [ ] **Step 4: Run — expect green.**

**Verify:** `test_publishAssetPayloadShape` passes.

- [ ] **Step 5: Commit.** `git commit -m "feat(sp2): add publishAssetPayload pure helper"`

---

## Task 2: Route `SocketClient.publishAsset` through the pure helper

**Files:** Modify `Backyamon/Models/AssetModels.swift`.

No behavior change — share the testable helper so the wire payload is covered by Task 1.

- [ ] **Step 1: This is a refactor with no new test;** the existing `test_publishAssetPayloadShape`
  plus the full `SampleTests` suite is the guard. Edit `publishAsset`:

Replace the inline payload in `SocketClient.publishAsset` (currently
`payload: ["assetId": assetId]`) with the helper:

```swift
    /// Publish a private asset to the community gallery.
    func publishAsset(assetId: String) async throws {
        let dict = try await emitWithAck(
            event: "publish-asset",
            payload: publishAssetPayload(assetId: assetId)
        )
        if let err = dict["error"] as? String {
            throw SocketClientError.server(err)
        }
    }
```

- [ ] **Step 2: Run the full suite.**
```
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests
```

**Verify:** Suite green; the project still compiles (`publishAsset` is unchanged in behavior).

- [ ] **Step 3: Commit.** `git commit -m "refactor(sp2): publishAsset uses publishAssetPayload helper"`

---

## Task 3: Pure helper — `filterAssets(_:type:search:)`

**Files:** Modify `Backyamon/Online/SampleUpload.swift`; modify `SampleTests/SP2GalleryTests.swift`.

This is the single source of truth for gallery filtering: type filter + case-insensitive title
search, **preserving input order** (the array is already server-sorted newest-first; we never
re-sort).

- [ ] **Step 1: Add the failing tests.**

```swift
    // Add inside SP2GalleryTests
    func test_filterAssets_typeOnly() {
        let rows = [sfx("1", title: "Drum Hit", slot: "dice-roll"),
                    music("2", title: "Reggae Loop"),
                    piece("3", title: "Gold Stone")]
        let result = filterAssets(rows, type: .sfx, search: "")
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func test_filterAssets_searchCaseInsensitive() {
        let rows = [sfx("1", title: "Drum Hit", slot: "dice-roll"),
                    music("2", title: "Reggae Loop")]
        let result = filterAssets(rows, type: nil, search: "reggae")
        XCTAssertEqual(result.map(\.id), ["2"])
    }

    func test_filterAssets_typeAndSearchCombined() {
        let rows = [sfx("1", title: "Snare", slot: "dice-roll"),
                    sfx("2", title: "Kick Drum", slot: "piece-move"),
                    music("3", title: "Drum Track")]
        let result = filterAssets(rows, type: .sfx, search: "drum")
        XCTAssertEqual(result.map(\.id), ["2"])
    }

    func test_filterAssets_preservesInputOrder() {
        // Rows arrive already newest-first (server desc(createdAt)); never re-sort.
        let rows = [music("a", title: "New", createdAt: 300),
                    music("b", title: "Mid", createdAt: 200),
                    music("c", title: "Old", createdAt: 100)]
        let result = filterAssets(rows, type: nil, search: "")
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
    }

    func test_filterAssets_searchMissReturnsEmpty() {
        let rows = [sfx("1", title: "Snare", slot: "dice-roll")]
        XCTAssertTrue(filterAssets(rows, type: nil, search: "zzz").isEmpty)
    }
```

- [ ] **Step 2: Run — expect compile failure** (`filterAssets` undefined).

- [ ] **Step 3: Implement the helper** in `SampleUpload.swift`:

```swift
/// Filter a (server-sorted) asset list by optional `AssetType` and a
/// case-insensitive title substring. Input order is preserved — the array is
/// already newest-first from the server, so we never re-sort.
func filterAssets(_ assets: [Asset], type: AssetType?, search: String) -> [Asset] {
    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return assets.filter { asset in
        if let type = type, asset.type != type { return false }
        if !trimmed.isEmpty,
           asset.title.range(of: trimmed, options: .caseInsensitive) == nil {
            return false
        }
        return true
    }
}
```

- [ ] **Step 4: Run — expect green.**

**Verify:** all five `filterAssets` tests pass.

- [ ] **Step 5: Commit.** `git commit -m "feat(sp2): add filterAssets pure helper (type + title search)"`

---

## Task 4: Expose a read-only slot lookup on `AssetManager`

**Files:** Modify `Backyamon/Audio/AssetManager.swift`; modify `SampleTests/SP2GalleryTests.swift`.

The USE toast must know whether an SFX slot already held a *different* asset before equipping.
`prefs` is `private`; expose a tiny read-only accessor over the already-public `equippedSFXIds`.
Also pin the USE/USING label correctness: a published sfx gallery row must round-trip its slot
through `decodeSfxMetadata`, so `isEquipped` returns true after `equipAsset`.

- [ ] **Step 1: Add the failing tests.**

```swift
    // Add inside SP2GalleryTests
    @MainActor
    func test_equippedSfxId_forSlotReflectsEquip() async {
        let mgr = AssetManager.shared
        let socket = SocketClient()                 // not connected; equipAsset writes prefs locally
        let row = sfx("foreign-1", title: "Boom", slot: "victory")
        XCTAssertNil(mgr.equippedSfxId(forSlot: "victory"))
        await mgr.equipAsset(row, socket: socket)
        XCTAssertEqual(mgr.equippedSfxId(forSlot: "victory"), "foreign-1")
        // USE/USING label correctness: the same gallery row reads as equipped.
        XCTAssertTrue(mgr.isEquipped(row))
        // cleanup so we do not leak prefs across tests
        await mgr.toggleEquip(row, socket: socket)
        XCTAssertNil(mgr.equippedSfxId(forSlot: "victory"))
    }
```

> If `SocketClient()` has no zero-arg init in this codebase, construct it with the same
> initializer the existing tests/views use (grep `SocketClient(` in `Backyamon/`); the equip
> path only touches the socket inside `loadEquippedAssets`, which no-ops without equipped network
> assets to resolve, so any constructible instance is fine.

- [ ] **Step 2: Run — expect compile failure** (`equippedSfxId(forSlot:)` undefined).

- [ ] **Step 3: Implement** in `AssetManager.swift` (in the public API section, near `isEquipped`):

```swift
    /// The asset id currently equipped in a given SFX slot, if any. Read-only;
    /// used by the gallery USE flow to detect a slot replacement.
    func equippedSfxId(forSlot slot: String) -> String? {
        equippedSFXIds[slot]
    }
```

- [ ] **Step 4: Run — expect green.**

**Verify:** `test_equippedSfxId_forSlotReflectsEquip` passes, including `isEquipped(row) == true`.

- [ ] **Step 5: Commit.** `git commit -m "feat(sp2): expose AssetManager.equippedSfxId(forSlot:) for USE toast"`

---

## Task 5: Wire `filterAssets` + searchText into `GalleryViewModel`

**Files:** Modify `Backyamon/Views/GalleryView.swift`.

Route the existing `filteredAssets` through the pure helper and add `searchText`. This is a small
behavioral change covered by the Task 3 unit tests for the helper; the VM wiring is verified by
the suite still compiling/passing plus manual run.

- [ ] **Step 1: Map the existing `Filter` enum to an `AssetType?`.** Add to `GalleryViewModel.Filter`:

```swift
        var assetType: AssetType? {
            switch self {
            case .all:   return nil
            case .piece: return .piece
            case .sfx:   return .sfx
            case .music: return .music
            }
        }
```

- [ ] **Step 2: Add `searchText` and rewrite `filteredAssets`.** In `GalleryViewModel`:

```swift
    @Published var searchText: String = ""

    var filteredAssets: [Asset] {
        filterAssets(assets, type: filter.assetType, search: searchText)
    }
```
(Delete the old `switch filter { ... }` body of `filteredAssets`.)

- [ ] **Step 3: Run the suite.**
```
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests
```

**Verify:** suite green; project compiles. (The helper's own behavior is already unit-tested.)

- [ ] **Step 4: Commit.** `git commit -m "feat(sp2): GalleryViewModel filteredAssets via filterAssets + searchText"`

---

## Task 6: Search field + no-match empty state in `GalleryView`

**Files:** Modify `Backyamon/Views/GalleryView.swift`.

Add a search `TextField` above the list and distinguish "no search match" from "empty gallery".
UI-layer change; verified by manual run + the existing helper tests.

- [ ] **Step 1: Add a search `TextField`** above the list (below the filter pills), bound to
  `vm.searchText`, Theme-styled, with a clear affordance:

```swift
        TextField("Search samples", text: $vm.searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(Theme.serif(14))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .accessibilityLabel("Search samples")
```

- [ ] **Step 2: Distinguish the empty states.** Where `vm.filteredAssets.isEmpty` currently
  shows the generic empty view, branch on `vm.searchText`:

```swift
                } else if vm.filteredAssets.isEmpty {
                    if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        emptyGalleryView          // existing generic empty state
                    } else {
                        noSearchMatchView         // new: "No samples match \(vm.searchText)"
                    }
                }
```
Add a `noSearchMatchView` mirroring the existing empty-state styling with copy like
`No samples match “\(vm.searchText)”`.

- [ ] **Step 3: Run + manual check.** Run the suite (green), then run the app and confirm
  searching narrows the list and a no-match query shows the distinct copy.

**Verify:** suite green; manual: search filters live; no-match copy differs from empty-library copy.

- [ ] **Step 4: Commit.** `git commit -m "feat(sp2): gallery search field + no-match empty state"`

---

## Task 7: Music inline preview in `GalleryView`

**Files:** Modify `Backyamon/Views/GalleryView.swift`.

`togglePreview` is already type-agnostic; only `preview(for:)` gates music out. Render the same
play/stop Button for `.music`, falling back to the `music.note` icon only when `asset.url == nil`.

- [ ] **Step 1: Replace the `.music` arm of `preview(for:)`:**

```swift
        case .music:
            if asset.url != nil {
                Button {
                    vm.togglePreview(asset)
                } label: {
                    Image(systemName: vm.previewingId == asset.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(red)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(vm.previewingId == asset.id ? "Stop preview" : "Preview music")
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(red)
            }
```

- [ ] **Step 2: Ensure preview stops on disappear.** Confirm `GalleryView` calls
  `vm.teardown()` (or equivalent that stops `previewPlayer`) in `.onDisappear`; add it if absent.

- [ ] **Step 3: Run + manual check.** Suite green; run the app, tap a music row's play button,
  confirm it plays and the icon toggles to stop, and that re-tap / leaving the screen stops it.

**Verify:** suite green; manual: music previews with the same play/stop control as SFX; stops on teardown.

- [ ] **Step 4: Commit.** `git commit -m "feat(sp2): inline music preview in gallery (reuse SFX pattern)"`

---

## Task 8: USE/USING relabel + slot-aware confirmation toast

**Files:** Modify `Backyamon/Views/GalleryView.swift`.

Relabel the action and add a slot-aware toast so a silent SFX slot replacement is surfaced.

- [ ] **Step 1: Relabel the button.** Change the gallery row action text
  `equipped ? "UNEQUIP" : "EQUIP"` → `equipped ? "USING" : "USE"` (keep
  `Task { await vm.toggleEquip(asset) }` underneath).

- [ ] **Step 2: Add toast state to `GalleryViewModel`:**

```swift
    @Published var toastMessage: String?

    func use(_ asset: Asset) async {
        let wasEquipped = isEquipped(asset)
        // Detect a prior occupant of this SFX slot before equipping.
        var replacedSlot: String?
        if !wasEquipped, asset.type == .sfx,
           let slot = asset.decodeSfxMetadata()?.slot,
           let prior = AssetManager.shared.equippedSfxId(forSlot: slot),
           prior != asset.id {
            replacedSlot = slot
        }
        await AssetManager.shared.toggleEquip(asset, socket: client)
        if wasEquipped {
            toastMessage = "Removed from your game"
        } else if let slot = replacedSlot {
            toastMessage = "Replaced your \(slot) sound"
        } else {
            toastMessage = "Added to your game"
        }
    }
```
Point the USE button at `vm.use(asset)` instead of `vm.toggleEquip(asset)`.

- [ ] **Step 3: Render the toast.** Add a lightweight transient overlay in `GalleryView` that
  shows `vm.toastMessage` for ~2s then clears it (auto-dismiss via a `Task`/`onChange`), styled
  with Theme tokens. Keep it non-blocking.

- [ ] **Step 4: Run + manual check.** Suite green. Manual: equip a foreign sfx into an empty slot
  → "Added to your game"; equip a *different* sfx into the same slot → "Replaced your <slot> sound";
  tap USING (unequip) → "Removed from your game".

**Verify:** suite green; manual: toast copy is slot-aware and the slot-replacement case is surfaced.

- [ ] **Step 5: Commit.** `git commit -m "feat(sp2): USE/USING relabel + slot-aware confirmation toast"`

---

## Task 9: Reload-on-appear so freshly published assets show up

**Files:** Modify `Backyamon/Views/GalleryView.swift`.

Each view owns its own `SocketClient`; a sample published in `MyStuff` won't appear in the Gallery
until the Gallery reloads. Add a refresh on re-appear.

- [ ] **Step 1: Reload on re-appear.** In `GalleryView`, after the initial `.task { await vm.start() }`,
  add an `.onAppear` (or `.refreshable`) that triggers `vm.reload()` when the connection is already
  established (guard against double-loading on first appearance):

```swift
        .onAppear {
            if vm.connected { Task { await vm.reload() } }
        }
```

- [ ] **Step 2: Run + manual check.** Suite green. Manual: publish a sample in MyStuff, switch to
  Gallery, confirm it appears (after the reload) without restarting the app.

**Verify:** suite green; manual: just-published asset appears on Gallery re-appear.

- [ ] **Step 3: Commit.** `git commit -m "feat(sp2): reload gallery on re-appear for cross-view freshness"`

---

## Task 10: PUBLISH button + optimistic publish in `MyStuffView`

**Files:** Modify `Backyamon/Views/MyStuffView.swift`.

The headline gap. Add a PUBLISH button on owned **audio** rows (`status == .private`), wire it to
`publishAsset`, optimistically flip the status (rebuilding the `Asset` element since `status` is
`let`), then `reload()` to confirm; revert + error on failure; soft-error if the flip didn't take.

- [ ] **Step 1: Add `publish(_:)` to `MyStuffViewModel`:**

```swift
    func publish(_ asset: Asset) async {
        guard asset.status == .private else { return }
        guard let idx = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        let original = assets[idx]
        // Optimistic flip — Asset.status is `let`, so rebuild the element.
        assets[idx] = Asset(id: original.id, creatorId: original.creatorId, type: original.type,
                            title: original.title, status: .published, metadata: original.metadata,
                            r2Key: original.r2Key, url: original.url,
                            createdAt: original.createdAt, updatedAt: original.updatedAt)
        do {
            try await client.publishAsset(assetId: asset.id)
            await reload()  // confirm from the server
            // Soft-guard: if the server did not actually flip it (e.g. ownership mismatch).
            if let now = assets.first(where: { $0.id == asset.id }), now.status != .published {
                errorMessage = "Publish didn't take effect."
            }
        } catch {
            // Revert the optimistic change and surface the failure.
            if let i = assets.firstIndex(where: { $0.id == asset.id }) { assets[i] = original }
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 2: Add the PUBLISH button** in `assetRow`'s action area. Gate it to owned audio rows
  that are private; keep the existing `· PUBLISHED` badge for the published case. (All rows in
  MyStuff are the user's own, so the only extra gate is `type == .sfx || type == .music` and
  `status == .private`.)

```swift
                    if (asset.type == .sfx || asset.type == .music), asset.status == .private {
                        Button {
                            Task { await vm.publish(asset) }
                        } label: {
                            Text("PUBLISH")
                                .font(Theme.serif(12))
                                .foregroundStyle(Theme.gold)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Publish to community gallery")
                    }
```
Keep existing EQUIP/trash buttons and 44pt touch targets intact.

- [ ] **Step 3: Run + manual check.** Suite green. Manual: a private audio row shows PUBLISH;
  tapping it flips the badge to `· PUBLISHED` immediately (optimistic) and stays after `reload()`.
  Pieces show no PUBLISH button. A forced RPC error reverts the badge and shows `errorMessage`.

**Verify:** suite green; manual: private audio rows publish; badge flips; pieces excluded; errors revert.

- [ ] **Step 4: Commit.** `git commit -m "feat(sp2): publish action on owned audio rows in MyStuff"`

---

## Task 11: Full-suite verification + xcodegen sanity

**Files:** none (verification only).

- [ ] **Step 1: Regenerate and run the entire `SampleTests` suite once more.**
```
xcodegen generate
xcodebuild test -scheme Backyamon -destination 'platform=iOS Simulator,id=F277ABC0-BCCF-4D05-BBBE-2EF2C717596E' -only-testing:SampleTests
```

**Verify:** all SP2 tests (publishAssetPayload, filterAssets x5, equippedSfxId round-trip) and the
pre-existing SampleTests are green; the app target compiles.

- [ ] **Step 2: Manual smoke of the full loop on-device:** publish a private sample in MyStuff →
  switch to Gallery (it appears on re-appear) → preview a music sample → tap USE (toast confirms,
  slot-aware) → start a game and confirm the equipped sample is heard.

- [ ] **Step 3: Final commit if any cleanup was needed.**
  `git commit -m "chore(sp2): final verification pass"`

---

## Notes on cut / deferred scope (do not implement)

- **Unpublish:** the server has no `unpublish-asset` event (verified absent in
  `/Users/suki/dev/backyamon/apps/server/src/index.ts`). Do not add `unpublishAsset` — it would
  hang on the 10s `emitWithAck` timeout. Removal stays on the existing trash/`deleteAsset`.
- **Client recency sort:** the server already orders `desc(createdAt)`; `filterAssets` preserves
  input order on purpose. Do not add a client sort.
- **Per-pill server type fetch:** keep fetching ALL once and filtering client-side (instant). Do
  not pass `type` to `listGallery` per pill.
- **iOS piece publish:** PUBLISH is intentionally audio-only.
