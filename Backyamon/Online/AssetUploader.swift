import Foundation

/// Orchestrates a single sample upload: create the asset row (presigned url),
/// then PUT the file bytes. Network/socket are injected as closures for testing.
struct AssetUploader {
    /// (type, title, metadata, contentType, fileSize) -> (id, uploadUrl?)
    var createAsset: (AssetType, String, String, String, Int) async throws -> (id: String, uploadUrl: String?)
    /// (data, url, contentType) -> Void  (PUT the bytes)
    var putData: (Data, URL, String) async throws -> Void

    static let contentType = "audio/mp4"

    /// Returns the new asset id. Throws on create or upload failure.
    func uploadSample(fileURL: URL, title: String, kind: SampleKind, durationMs: Int) async throws -> String {
        let data = try Data(contentsOf: fileURL)
        let metadata = sampleMetadataJSON(kind: kind, durationMs: durationMs, fileSize: data.count)
        let (id, uploadUrl) = try await createAsset(kind.assetType, title, metadata, Self.contentType, data.count)
        if let uploadUrl, let url = URL(string: uploadUrl) {
            try await putData(data, url, Self.contentType)
        }
        return id
    }
}

extension AssetUploader {
    /// Production wiring: real socket + URLSession upload.
    static func live(socket: SocketClient) -> AssetUploader {
        AssetUploader(
            createAsset: { type, title, metadata, contentType, fileSize in
                try await socket.createAsset(type: type, title: title, metadata: metadata,
                                             contentType: contentType, fileSize: fileSize)
            },
            putData: { data, url, contentType in
                let req = makeUploadRequest(url: url, contentType: contentType)
                let (_, response) = try await URLSession.shared.upload(for: req, from: data)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw SocketClientError.server("Upload failed")
                }
            }
        )
    }
}
