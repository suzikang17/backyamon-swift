import SwiftUI
import UniformTypeIdentifiers

/// Record or import a sample, bind it to a Riddim engine voice, upload, and equip.
struct AssignVoiceView: View {
    let socket: SocketClient
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var recordedURL: URL?
    @State private var importedURL: URL?
    @State private var title = ""
    @State private var voice: InstrumentID = .kick
    @State private var rootMidi: Int = 33
    @State private var isImporting = false
    @State private var isSaving = false
    @State private var errorText: String?

    private var pitched: Bool { RiddimVoiceLoader.defaultRoot(for: voice) != nil }
    private var sourceURL: URL? { recordedURL ?? importedURL }

    // Client-side caps to bound loadMono's single-shot convert.
    private let maxBytes = 5 * 1024 * 1024

    var body: some View {
        NavigationStack {
            Form {
                Section("Sample") {
                    Button(recorder.isRecording ? "Stop Recording"
                           : (recordedURL == nil ? "Record" : "Re-record")) { record() }
                    Button("Import audio") { isImporting = true }
                    if let url = sourceURL { Text(url.lastPathComponent).font(.caption) }
                }
                Section("Voice") {
                    Picker("Instrument", selection: $voice) {
                        ForEach(InstrumentID.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .onChange(of: voice) { _, new in
                        rootMidi = RiddimVoiceLoader.defaultRoot(for: new) ?? rootMidi
                    }
                    if pitched {
                        Stepper("Root MIDI: \(rootMidi)", value: $rootMidi, in: 12...96)
                    }
                }
                TextField("Title", text: $title)
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("Use as instrument voice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(sourceURL == nil || title.isEmpty || isSaving)
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { importedURL = url }
            }
        }
    }

    private func record() {
        if recorder.isRecording {
            recordedURL = recorder.stop()
        } else {
            recorder.requestPermission { granted in
                if granted { recorder.start() }
                else { errorText = "Microphone access denied. Import a file instead." }
            }
        }
    }

    private func save() async {
        guard let url = sourceURL else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maxBytes else { errorText = "Sample too large"; return }
            let durationMs = audioDurationMs(of: url)
            let ct = contentType(for: url)
            let kind = SampleKind.riddimVoice(voice: voice, rootMidiNote: pitched ? rootMidi : nil)
            let id = try await AssetUploader.live(socket: socket)
                .uploadSample(fileURL: url, title: title, kind: kind, durationMs: durationMs, contentType: ct)
            await AssetManager.shared.equipAsset(assetId: id, socket: socket)
            onSaved()
            dismiss()
        } catch {
            errorText = "Upload failed"
        }
    }

    private func contentType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return AssetUploader.contentType
    }
}
