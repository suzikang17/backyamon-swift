import SwiftUI

/// Minimal trigger: render the riddim loop (with installed voice overrides) and
/// loop it. This is the audibility surface for SP3.
struct RiddimPlayView: View {
    @StateObject private var holder = RiddimEngineHolder.shared

    var body: some View {
        VStack(spacing: 16) {
            if holder.isAvailable {
                Button(holder.isGenerating ? "Generating…" : "Generate & Play") {
                    Task { await holder.regenerateAndPlay() }
                }
                .disabled(holder.isGenerating)
                Button("Stop") { holder.stop() }
            } else {
                Text("Riddim engine unavailable").foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Riddim")
    }
}
