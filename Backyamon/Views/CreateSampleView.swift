import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Record or import an audio sample, name it, choose what it is, and upload it.
struct CreateSampleView: View {
    /// Pass a connected SocketClient (e.g. from MyStuffViewModel) and a reload hook.
    let socket: SocketClient
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var fileURL: URL?
    @State private var durationMs = 0
    @State private var title = ""
    @State private var isMusic = false
    @State private var slot = "piece-move"
    @State private var showImporter = false
    @State private var busy = false
    @State private var error: String?

    private let slots = ["dice-roll","piece-move","piece-hit","bear-off","victory",
                         "defeat","double-offered","ya-mon","turn-start"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture") {
                    Button(recorder.isRecording ? "Stop Recording" : "Record") {
                        if recorder.isRecording {
                            fileURL = recorder.stop()
                            if let u = fileURL { durationMs = audioDurationMs(of: u) }
                        } else {
                            recorder.requestPermission { granted in
                                if granted { recorder.start() }
                                else { error = "Microphone access denied. Import a file instead." }
                            }
                        }
                    }
                    Button("Import from Files") { showImporter = true }
                    if let u = fileURL {
                        Text("Loaded: \(u.lastPathComponent) (\(durationMs) ms)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("Music loop/track", isOn: $isMusic)
                    if !isMusic {
                        Picker("Sound slot", selection: $slot) {
                            ForEach(slots, id: \.self) { Text($0) }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Create Sample")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(fileURL == nil || title.isEmpty || busy)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result { importFile(url) }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    private func importFile(_ url: URL) {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let dest = AudioRecorder.makeTempURL().deletingPathExtension()
            .appendingPathExtension(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            fileURL = dest
            durationMs = audioDurationMs(of: dest)
        } catch {
            self.error = "Could not import that file."
        }
    }

    private func save() async {
        guard let url = fileURL else { return }
        busy = true; error = nil
        let kind: SampleKind = isMusic ? .music : .soundEffect(slot: slot)
        do {
            _ = try await AssetUploader.live(socket: socket)
                .uploadSample(fileURL: url, title: title, kind: kind, durationMs: durationMs)
            busy = false
            onSaved()
            dismiss()
        } catch {
            busy = false
            self.error = "Upload failed. Check your connection and try again."
        }
    }
}
