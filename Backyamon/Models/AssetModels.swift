import Foundation

// MARK: - Asset Types
//
// Mirror of the server's `assets` table wire form. The server emits asset
// rows with an extra `url` field (presigned public URL) when an `r2Key` is
// present. The `metadata` field is a JSON-encoded string whose shape depends
// on `type` — `PieceMetadata`, `SfxMetadata`, or `MusicMetadata` below.

/// Asset categories supported by the Creation Station / Gallery flow.
enum AssetType: String, Codable {
    case piece
    case sfx
    case music
}

/// Publication status of an asset.
enum AssetStatus: String, Codable {
    case `private`
    case published
    case removed
}

/// One asset row from the server. `r2Key`/`url` are nil for purely
/// metadata-only assets (e.g. SVG pieces). `metadata` is a JSON string.
struct Asset: Decodable, Identifiable, Hashable {
    let id: String
    let creatorId: String
    let type: AssetType
    let title: String
    let status: AssetStatus
    let metadata: String
    let r2Key: String?
    let url: String?
    let createdAt: Int64
    let updatedAt: Int64
}

// MARK: - Typed metadata payloads
//
// `Asset.metadata` is a JSON string. The shape depends on `type`. These
// helpers decode whichever variant is appropriate for a given asset.

/// Piece SVG markup: two strings, one per player colour.
struct PieceMetadata: Decodable, Hashable {
    let svg_gold: String
    let svg_red: String
}

/// SFX metadata: which slot it overrides (matches a `GameSound` case), plus
/// duration/size for display.
struct SfxMetadata: Decodable, Hashable {
    let slot: String
    let duration_ms: Int
    let file_size: Int?
    let root_midi_note: Int?
}

/// Music metadata: duration/size for display.
struct MusicMetadata: Decodable, Hashable {
    let duration_ms: Int
    let file_size: Int?
}

// MARK: - Metadata decoding

extension Asset {
    /// Decode the SVG payload for piece assets, returning nil on any error.
    func decodePieceMetadata() -> PieceMetadata? {
        guard let data = metadata.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PieceMetadata.self, from: data)
    }

    /// Decode the SFX payload for sfx assets, returning nil on any error.
    func decodeSfxMetadata() -> SfxMetadata? {
        guard let data = metadata.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SfxMetadata.self, from: data)
    }

    /// Decode the music payload, returning nil on any error.
    func decodeMusicMetadata() -> MusicMetadata? {
        guard let data = metadata.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MusicMetadata.self, from: data)
    }
}

// MARK: - Helpers

/// Map the server's SFX slot string (web-style hyphenated names) to a
/// `GameSound` case for use with `SoundManager`. Unknown slots return nil.
func gameSoundForSlot(_ slot: String) -> GameSound? {
    switch slot {
    case "dice-roll": return .diceRoll
    case "piece-move": return .pieceMove
    case "piece-hit": return .pieceHit
    case "bear-off": return .bearOff
    case "victory": return .victory
    case "defeat": return .defeat
    case "double-offered": return .doubleOffered
    case "ya-mon": return .yaMon
    case "turn-start": return .turnStart
    default: return nil
    }
}

/// Map a `riddim-<voice>` slot string back to its `InstrumentID`. Non-riddim or
/// unknown slots return nil.
func riddimVoice(forSlot slot: String) -> InstrumentID? {
    let prefix = "riddim-"
    guard slot.hasPrefix(prefix) else { return nil }
    return InstrumentID(rawValue: String(slot.dropFirst(prefix.count)))
}

/// Format a duration in milliseconds as `m:ss`.
func formatAssetDuration(_ ms: Int) -> String {
    let totalSeconds = (ms + 500) / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - SocketClient asset RPCs

extension SocketClient {
    /// Fetch the current user's assets. Optionally filter by `AssetType`.
    func listMyAssets(type: AssetType? = nil) async throws -> [Asset] {
        let payload: [String: Any] = type.map { ["type": $0.rawValue] } ?? [:]
        let dict = try await emitWithAck(event: "list-my-assets", payload: payload)
        if let err = dict["error"] as? String {
            throw SocketClientError.server(err)
        }
        return decodeAssetList(dict)
    }

    /// Fetch the published community gallery. Optionally filter by `AssetType`.
    func listGallery(type: AssetType? = nil) async throws -> [Asset] {
        let payload: [String: Any] = type.map { ["type": $0.rawValue] } ?? [:]
        let dict = try await emitWithAck(event: "list-gallery", payload: payload)
        if let err = dict["error"] as? String {
            throw SocketClientError.server(err)
        }
        return decodeAssetList(dict)
    }

    /// Delete one of the current user's assets. Throws on server error.
    func deleteAsset(assetId: String) async throws {
        let dict = try await emitWithAck(
            event: "delete-asset",
            payload: ["assetId": assetId]
        )
        if let err = dict["error"] as? String {
            throw SocketClientError.server(err)
        }
    }

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

    /// Create an asset row on the server and get a presigned upload URL back.
    /// Mirrors the web `/create` flow. Returns the new asset id + optional PUT url.
    func createAsset(type: AssetType, title: String, metadata: String,
                     contentType: String, fileSize: Int) async throws -> (id: String, uploadUrl: String?) {
        let payload = createAssetPayload(type: type, title: title, metadata: metadata,
                                         contentType: contentType, fileSize: fileSize)
        let dict = try await emitWithAck(event: "create-asset", payload: payload)
        return try parseCreateAssetAck(dict)
    }
}

/// Decode the `{ assets: [...] }` envelope returned by the server. Unknown /
/// malformed rows are silently dropped.
private func decodeAssetList(_ dict: [String: Any]) -> [Asset] {
    guard let arr = dict["assets"] as? [[String: Any]] else { return [] }
    return arr.compactMap { decodeAsset($0) }
}

private func decodeAsset(_ d: [String: Any]) -> Asset? {
    guard let id = d["id"] as? String,
          let creatorId = d["creatorId"] as? String,
          let typeStr = d["type"] as? String,
          let type = AssetType(rawValue: typeStr),
          let title = d["title"] as? String,
          let statusStr = d["status"] as? String,
          let status = AssetStatus(rawValue: statusStr) else { return nil }

    let metadata = (d["metadata"] as? String) ?? ""
    let r2Key = d["r2Key"] as? String
    let url = d["url"] as? String

    // createdAt/updatedAt may arrive as Int or Int64 depending on payload size.
    let createdAt: Int64
    if let v = d["createdAt"] as? Int64 {
        createdAt = v
    } else if let v = d["createdAt"] as? Int {
        createdAt = Int64(v)
    } else if let v = d["createdAt"] as? Double {
        createdAt = Int64(v)
    } else {
        createdAt = 0
    }
    let updatedAt: Int64
    if let v = d["updatedAt"] as? Int64 {
        updatedAt = v
    } else if let v = d["updatedAt"] as? Int {
        updatedAt = Int64(v)
    } else if let v = d["updatedAt"] as? Double {
        updatedAt = Int64(v)
    } else {
        updatedAt = 0
    }

    return Asset(
        id: id,
        creatorId: creatorId,
        type: type,
        title: title,
        status: status,
        metadata: metadata,
        r2Key: r2Key,
        url: url,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}
