import SwiftUI
import AVFoundation

// MARK: - GalleryView

/// Community gallery — shows the `published` assets so anyone can equip them.
/// Mirrors the web `GalleryPage`.
struct GalleryView: View {
    @StateObject private var vm = GalleryViewModel()

    private let bg = Color(red: 0.06, green: 0.14, blue: 0.08)
    private let gold = Color(red: 0.85, green: 0.72, blue: 0.45)
    private let green = Color(red: 0.0, green: 0.55, blue: 0.32)
    private let red = Color(red: 0.7, green: 0.2, blue: 0.2)
    private let cream = Color(red: 0.96, green: 0.94, blue: 0.88)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                statusBar
                filterPicker

                if vm.loading {
                    Spacer()
                    ProgressView().tint(gold)
                    Spacer()
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if vm.filteredAssets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(vm.filteredAssets) { asset in
                                assetRow(asset)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.start()
        }
        .onDisappear {
            vm.teardown()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 4) {
            Text("GALLERY")
                .font(.custom("Georgia-Bold", size: 28))
                .tracking(4)
                .foregroundStyle(gold)
            Text("community creations")
                .font(.custom("Georgia", size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(vm.connected ? green : (vm.connecting ? gold : red))
                .frame(width: 8, height: 8)
            Text(
                vm.connecting
                    ? "Connecting..."
                    : (vm.connected ? "Connected" : "Disconnected")
            )
            .font(.custom("Georgia", size: 11))
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.bottom, 8)
    }

    private var filterPicker: some View {
        HStack(spacing: 6) {
            ForEach(GalleryViewModel.Filter.allCases, id: \.self) { f in
                Button {
                    vm.filter = f
                } label: {
                    Text(f.label)
                        .font(.custom("Georgia-Bold", size: 11))
                        .tracking(1.5)
                        .foregroundStyle(vm.filter == f ? bg : Color.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(vm.filter == f ? gold : Color.white.opacity(0.06))
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(message)
                .font(.custom("Georgia", size: 13))
                .foregroundStyle(red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("RETRY") {
                Task { await vm.reload() }
            }
            .font(.custom("Georgia-Bold", size: 12))
            .tracking(3)
            .foregroundStyle(bg)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(gold)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Gallery is empty")
                .font(.custom("Georgia-Bold", size: 16))
                .foregroundStyle(gold)
            Text("No community creations published yet — be the first.")
                .font(.custom("Georgia", size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    @ViewBuilder
    private func assetRow(_ asset: Asset) -> some View {
        let equipped = vm.isEquipped(asset)
        HStack(spacing: 12) {
            preview(for: asset)
                .frame(width: 52, height: 52)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(asset.title)
                        .font(.custom("Georgia-Bold", size: 14))
                        .foregroundStyle(cream)
                        .lineLimit(1)
                    if equipped {
                        Text("EQUIPPED")
                            .font(.custom("Georgia-Bold", size: 8))
                            .tracking(1)
                            .foregroundStyle(bg)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(gold)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                HStack(spacing: 4) {
                    Text(typeBadge(asset))
                        .font(.custom("Georgia-Bold", size: 9))
                        .tracking(1.5)
                        .foregroundStyle(typeColor(asset))
                }
                Text("by \(asset.creatorId.prefix(8))")
                    .font(.custom("Georgia", size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                subtitleLine(for: asset)
            }

            Spacer()

            Button {
                Task { await vm.toggleEquip(asset) }
            } label: {
                Text(equipped ? "UNEQUIP" : "EQUIP")
                    .font(.custom("Georgia-Bold", size: 10))
                    .tracking(2)
                    .foregroundStyle(equipped ? bg : gold)
                    .frame(width: 76, height: 28)
                    .background(equipped ? gold : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(gold.opacity(equipped ? 0 : 0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(equipped ? gold.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func preview(for asset: Asset) -> some View {
        switch asset.type {
        case .piece:
            ZStack {
                Circle().fill(gold)
                Circle().stroke(Color.black.opacity(0.35), lineWidth: 2)
            }
            .padding(8)
        case .sfx:
            Button {
                vm.togglePreview(asset)
            } label: {
                Image(systemName: vm.previewingId == asset.id ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(green)
            }
        case .music:
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(red)
        }
    }

    @ViewBuilder
    private func subtitleLine(for asset: Asset) -> some View {
        switch asset.type {
        case .piece:
            EmptyView()
        case .sfx:
            if let meta = asset.decodeSfxMetadata() {
                Text("\(meta.slot) · \(formatAssetDuration(meta.duration_ms))")
                    .font(.custom("Georgia", size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        case .music:
            if let meta = asset.decodeMusicMetadata() {
                Text(formatAssetDuration(meta.duration_ms))
                    .font(.custom("Georgia", size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private func typeBadge(_ asset: Asset) -> String {
        switch asset.type {
        case .piece: return "PIECE"
        case .sfx: return "SFX"
        case .music: return "MUSIC"
        }
    }

    private func typeColor(_ asset: Asset) -> Color {
        switch asset.type {
        case .piece: return gold
        case .sfx: return green
        case .music: return red
        }
    }
}

// MARK: - View model

@MainActor
final class GalleryViewModel: ObservableObject {
    enum Filter: CaseIterable {
        case all, piece, sfx, music

        var label: String {
            switch self {
            case .all: return "ALL"
            case .piece: return "PIECES"
            case .sfx: return "SFX"
            case .music: return "MUSIC"
            }
        }
    }

    @Published var assets: [Asset] = []
    @Published var loading: Bool = true
    @Published var connecting: Bool = true
    @Published var connected: Bool = false
    @Published var errorMessage: String?
    @Published var filter: Filter = .all
    @Published var previewingId: String?

    let client: SocketClient
    private var previewPlayer: AVAudioPlayer?

    init() {
        self.client = SocketClient()
    }

    var filteredAssets: [Asset] {
        switch filter {
        case .all: return assets
        case .piece: return assets.filter { $0.type == .piece }
        case .sfx: return assets.filter { $0.type == .sfx }
        case .music: return assets.filter { $0.type == .music }
        }
    }

    func isEquipped(_ asset: Asset) -> Bool {
        AssetManager.shared.isEquipped(asset)
    }

    func start() async {
        connecting = true
        loading = true
        errorMessage = nil
        do {
            try await client.connect(maxRetries: 5)
            _ = try await client.register()
            connected = true
            connecting = false
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            connecting = false
            loading = false
        }
    }

    func reload() async {
        loading = true
        errorMessage = nil
        do {
            assets = try await client.listGallery()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func toggleEquip(_ asset: Asset) async {
        await AssetManager.shared.toggleEquip(asset, socket: client)
        objectWillChange.send()
    }

    func togglePreview(_ asset: Asset) {
        if previewingId == asset.id {
            previewPlayer?.stop()
            previewPlayer = nil
            previewingId = nil
            return
        }
        previewPlayer?.stop()
        previewPlayer = nil
        previewingId = nil

        guard let urlStr = asset.url, let url = URL(string: urlStr) else { return }
        previewingId = asset.id

        Task.detached(priority: .utility) { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let player = try AVAudioPlayer(data: data)
                player.prepareToPlay()
                await MainActor.run {
                    guard let self else { return }
                    if self.previewingId == asset.id {
                        self.previewPlayer = player
                        player.play()
                    }
                }
            } catch {
                await MainActor.run {
                    self?.previewingId = nil
                }
            }
        }
    }

    func teardown() {
        previewPlayer?.stop()
        previewPlayer = nil
        client.disconnect()
    }
}
