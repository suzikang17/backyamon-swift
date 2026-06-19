import Foundation

/// What a recorded/imported sample becomes when uploaded. Maps to the server's
/// existing `sfx` / `music` asset types (a dedicated `sample` type is future work).
enum SampleKind: Equatable {
    case soundEffect(slot: String)   // one-shot bound to a GameSound slot string
    case music                       // loop / track
    case riddimVoice(voice: InstrumentID, rootMidiNote: Int?)  // replaces a Riddim engine voice

    var assetType: AssetType {
        switch self {
        case .soundEffect: return .sfx
        case .music:       return .music
        case .riddimVoice: return .sfx
        }
    }
}

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

/// Build the JSON metadata string the server stores for a sample asset.
/// Shapes match `SfxMetadata` / `MusicMetadata` in AssetModels.swift.
func sampleMetadataJSON(kind: SampleKind, durationMs: Int, fileSize: Int) -> String {
    var dict: [String: Any]
    switch kind {
    case .soundEffect(let slot):
        dict = ["slot": slot, "duration_ms": durationMs, "file_size": fileSize]
    case .music:
        dict = ["duration_ms": durationMs, "file_size": fileSize]
    case .riddimVoice(let voice, let rootMidiNote):
        dict = ["slot": "riddim-\(voice.rawValue)", "duration_ms": durationMs, "file_size": fileSize]
        if let rootMidiNote { dict["root_midi_note"] = rootMidiNote }
    }
    let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    return String(data: data, encoding: .utf8) ?? "{}"
}

/// Payload dict for the server `create-asset` event (needsUpload always true here).
func createAssetPayload(type: AssetType, title: String, metadata: String,
                        contentType: String, fileSize: Int) -> [String: Any] {
    return [
        "type": type.rawValue,
        "title": title,
        "metadata": metadata,
        "needsUpload": true,
        "contentType": contentType,
        "fileSize": fileSize,
    ]
}

/// Parse the `create-asset` ack: `{id, uploadUrl}` on success or `{error}`.
func parseCreateAssetAck(_ dict: [String: Any]) throws -> (id: String, uploadUrl: String?) {
    if let err = dict["error"] as? String { throw SocketClientError.server(err) }
    guard let id = dict["id"] as? String else { throw SocketClientError.decoding("create-asset") }
    return (id, dict["uploadUrl"] as? String)
}

/// Build the presigned-R2 PUT request (body set by the caller / URLSession upload).
func makeUploadRequest(url: URL, contentType: String) -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = "PUT"
    req.setValue(contentType, forHTTPHeaderField: "Content-Type")
    return req
}

/// Payload dict for the server `publish-asset` event. Mirrors the inline
/// payload `SocketClient.publishAsset` builds, extracted so it is unit-testable.
func publishAssetPayload(assetId: String) -> [String: Any] {
    return ["assetId": assetId]
}
