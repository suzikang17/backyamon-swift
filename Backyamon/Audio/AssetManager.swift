import Foundation
import SwiftUI

/// Tracks the currently-equipped community assets and applies them to the
/// running app (audio, board rendering).
///
/// Persistence: a single set of preferences is stored in `UserDefaults` —
/// only the asset IDs. The actual SVG/audio payloads are re-fetched on demand
/// via `SocketClient.listMyAssets()` so the source of truth remains the
/// server.
@MainActor
final class AssetManager: ObservableObject {
    static let shared = AssetManager()

    // MARK: - Published surface
    //
    // `equippedPieceSvg` is the gold-piece SVG markup for the currently-
    // equipped custom piece, or `nil` when no custom piece is equipped.
    // `BoardView` (or any other renderer) can observe this to switch its
    // visual treatment.
    @Published private(set) var equippedPieceSvg: String?
    @Published private(set) var equippedPieceRedSvg: String?
    @Published private(set) var equippedPieceId: String?
    @Published private(set) var equippedMusicId: String?
    @Published private(set) var equippedSFXIds: [String: String] = [:]
    @Published private(set) var equippedRiddimIds: [String: String] = [:]

    private init() {
        loadPreferences()
    }

    // MARK: - Preference storage

    struct Prefs: Codable {
        var pieceSet: String?
        var music: String?
        var sfx: [String: String] = [:]
        var riddim: [String: String] = [:]

        init() {}

        // Custom decoding so persisted blobs from before a key existed
        // (e.g. pre-SP3 blobs with no `riddim`) still decode, defaulting
        // missing dictionaries to empty.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pieceSet = try c.decodeIfPresent(String.self, forKey: .pieceSet)
            music = try c.decodeIfPresent(String.self, forKey: .music)
            sfx = try c.decodeIfPresent([String: String].self, forKey: .sfx) ?? [:]
            riddim = try c.decodeIfPresent([String: String].self, forKey: .riddim) ?? [:]
        }
    }

    private static let prefsKey = "backyamon_asset_prefs_v1"

    /// Test seam: decode a persisted Prefs blob (tolerant of missing keys).
    static func decodePrefs(_ data: Data) -> Prefs? {
        try? JSONDecoder().decode(Prefs.self, from: data)
    }

    private var prefs: Prefs = Prefs() {
        didSet { savePreferences() }
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: Self.prefsKey),
              let decoded = try? JSONDecoder().decode(Prefs.self, from: data) else {
            return
        }
        prefs = decoded
        equippedPieceId = decoded.pieceSet
        equippedMusicId = decoded.music
        equippedSFXIds = decoded.sfx
        equippedRiddimIds = decoded.riddim
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.prefsKey)
        }
    }

    // MARK: - Public API

    /// Check whether a given asset is currently equipped (by user pref).
    func isEquipped(_ asset: Asset) -> Bool {
        switch asset.type {
        case .piece:
            return prefs.pieceSet == asset.id
        case .music:
            return prefs.music == asset.id
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return false }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return false }
                return prefs.riddim[voice.rawValue] == asset.id
            }
            return prefs.sfx[slot] == asset.id
        }
    }

    /// The asset id currently equipped in a given SFX slot, if any. Read-only;
    /// used by the gallery USE flow to detect a slot replacement.
    func equippedSfxId(forSlot slot: String) -> String? {
        equippedSFXIds[slot]
    }

    /// Toggle equip state for an asset. Equipping replaces any other asset in
    /// the same slot. After the preference update the underlying audio /
    /// visual state is reloaded via `loadEquippedAssets(socket:)`.
    func toggleEquip(_ asset: Asset, socket: SocketClient) async {
        if isEquipped(asset) {
            await unequipAsset(asset, socket: socket)
        } else {
            await equipAsset(asset, socket: socket)
        }
    }

    /// Equip an asset by updating preferences then reloading derived state.
    func equipAsset(_ asset: Asset, socket: SocketClient) async {
        applyEquip(asset)
        await loadEquippedAssets(socket: socket)
    }

    /// Unequip an asset by clearing the corresponding preference slot then
    /// reloading derived state.
    func unequipAsset(_ asset: Asset, socket: SocketClient) async {
        applyUnequip(asset)
        await loadEquippedAssets(socket: socket)
    }

    /// Synchronous pref mutation for equip (no network). Returns after persisting.
    func applyEquip(_ asset: Asset) {
        switch asset.type {
        case .piece:
            prefs.pieceSet = asset.id; equippedPieceId = asset.id
        case .music:
            prefs.music = asset.id; equippedMusicId = asset.id
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return }
                prefs.riddim[voice.rawValue] = asset.id
                equippedRiddimIds = prefs.riddim
            } else {
                prefs.sfx[slot] = asset.id
                equippedSFXIds = prefs.sfx
            }
        }
    }

    /// Synchronous pref mutation for unequip (no network).
    func applyUnequip(_ asset: Asset) {
        switch asset.type {
        case .piece:
            prefs.pieceSet = nil; equippedPieceId = nil
            equippedPieceSvg = nil; equippedPieceRedSvg = nil
        case .music:
            prefs.music = nil; equippedMusicId = nil
            SoundManager.shared.clearCustomMusic()
        case .sfx:
            guard let slot = asset.decodeSfxMetadata()?.slot else { return }
            if slot.hasPrefix("riddim-") {
                guard let voice = riddimVoice(forSlot: slot) else { return }
                prefs.riddim[voice.rawValue] = nil
                equippedRiddimIds = prefs.riddim
                RiddimEngineHolder.shared.sampleLibrary?.clearOverride(for: voice)
            } else {
                prefs.sfx[slot] = nil
                equippedSFXIds = prefs.sfx
                if let game = gameSoundForSlot(slot) {
                    SoundManager.shared.clearCustomSFX(slot: game)
                }
            }
        }
    }

    /// Test seam: wipe persisted prefs.
    func resetPrefsForTesting() {
        prefs = Prefs()
        equippedPieceId = nil; equippedMusicId = nil
        equippedSFXIds = [:]; equippedRiddimIds = [:]
        equippedPieceSvg = nil; equippedPieceRedSvg = nil
    }

    /// Convenience overload — equip by asset ID. Looks the asset up via
    /// `listMyAssets()` and `listGallery()`. Does nothing if the asset is
    /// not found.
    func equipAsset(assetId: String, socket: SocketClient) async {
        if let asset = await findAsset(byId: assetId, socket: socket) {
            await equipAsset(asset, socket: socket)
        }
    }

    /// Refetch the user's equipped assets and push them into SoundManager /
    /// `equippedPieceSvg`. Safe to call repeatedly — no-ops when nothing is
    /// equipped.
    func loadEquippedAssets(socket: SocketClient) async {
        // Bail early if nothing is equipped — no point hitting the server.
        guard prefs.pieceSet != nil || prefs.music != nil
              || !prefs.sfx.isEmpty || !prefs.riddim.isEmpty else {
            equippedPieceSvg = nil
            equippedPieceRedSvg = nil
            return
        }

        let myAssets: [Asset]
        do {
            myAssets = try await socket.listMyAssets()
        } catch {
            // Network failure — leave existing state in place.
            return
        }
        // Index by id for O(1) lookup; if the user equipped a gallery asset
        // they don't own we'll also try the gallery as a fallback below.
        var index: [String: Asset] = [:]
        for a in myAssets { index[a.id] = a }

        // Piece
        if let pieceId = prefs.pieceSet {
            var asset = index[pieceId]
            if asset == nil {
                asset = await findInGallery(id: pieceId, socket: socket)
            }
            if let asset, asset.type == .piece, let meta = asset.decodePieceMetadata() {
                equippedPieceSvg = meta.svg_gold
                equippedPieceRedSvg = meta.svg_red
            } else {
                equippedPieceSvg = nil
                equippedPieceRedSvg = nil
            }
        } else {
            equippedPieceSvg = nil
            equippedPieceRedSvg = nil
        }

        // SFX — load each one into SoundManager.
        SoundManager.shared.clearAllCustomSFX()
        for (slot, assetId) in prefs.sfx {
            guard let game = gameSoundForSlot(slot) else { continue }
            var asset = index[assetId]
            if asset == nil {
                asset = await findInGallery(id: assetId, socket: socket)
            }
            if let asset,
               asset.type == .sfx,
               let urlStr = asset.url,
               let url = URL(string: urlStr) {
                SoundManager.shared.loadCustomSFX(slot: game, url: url)
            }
        }

        // Riddim voices — resolve each and install as a library override.
        // Clear any stale overrides first (mirrors clearAllCustomSFX above) so
        // an unequipped-then-changed voice can't leave a stale override behind.
        if let library = RiddimEngineHolder.shared.sampleLibrary {
            library.clearAllOverrides()
        }
        if !prefs.riddim.isEmpty, let library = RiddimEngineHolder.shared.sampleLibrary {
            let loader = RiddimVoiceLoader.live(library: library)
            for (_, assetId) in prefs.riddim {
                var asset = index[assetId]
                if asset == nil { asset = await findInGallery(id: assetId, socket: socket) }
                guard let asset, let params = riddimOverrideParams(for: asset) else { continue }
                try? await loader.setVoice(url: params.url,
                                           rootMidiNote: params.rootMidiNote,
                                           for: params.voice)
            }
        }

        // Music
        if let musicId = prefs.music {
            var asset = index[musicId]
            if asset == nil {
                asset = await findInGallery(id: musicId, socket: socket)
            }
            if let asset,
               asset.type == .music,
               let urlStr = asset.url,
               let url = URL(string: urlStr) {
                SoundManager.shared.loadCustomMusic(url: url)
            } else {
                SoundManager.shared.clearCustomMusic()
            }
        } else {
            SoundManager.shared.clearCustomMusic()
        }
    }

    // MARK: - Helpers

    /// Extract the (voice, root, url) needed to install a riddim override from a
    /// resolved asset. Nil if the asset is not a riddim-slot sfx with a url.
    func riddimOverrideParams(for asset: Asset)
        -> (voice: InstrumentID, rootMidiNote: Int?, url: URL)? {
        guard asset.type == .sfx,
              let meta = asset.decodeSfxMetadata(),
              meta.slot.hasPrefix("riddim-"),
              let voice = riddimVoice(forSlot: meta.slot),
              let urlStr = asset.url, let url = URL(string: urlStr) else { return nil }
        return (voice, meta.root_midi_note, url)
    }

    private func findAsset(byId id: String, socket: SocketClient) async -> Asset? {
        if let mine = try? await socket.listMyAssets(),
           let hit = mine.first(where: { $0.id == id }) {
            return hit
        }
        return await findInGallery(id: id, socket: socket)
    }

    private func findInGallery(id: String, socket: SocketClient) async -> Asset? {
        guard let gallery = try? await socket.listGallery() else { return nil }
        return gallery.first(where: { $0.id == id })
    }
}
