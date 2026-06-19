import SwiftUI
import AVFoundation

// MARK: - GalleryView

/// Community gallery — shows the `published` assets so anyone can equip them.
/// Mirrors the web `GalleryPage`.
struct GalleryView: View {
    @StateObject private var vm = GalleryViewModel()

    private let bg = Theme.bg
    private let gold = Theme.gold
    private let green = Theme.green
    private let red = Theme.red
    private let cream = Theme.cream

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Theme.bgGlow,
                    Theme.bgDeep
                ],
                center: .top,
                startRadius: 80,
                endRadius: 600
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                statusBar
                filterPicker
                searchField

                if vm.loading {
                    Spacer()
                    ProgressView().tint(gold)
                    Spacer()
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if vm.filteredAssets.isEmpty {
                    if vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        emptyState
                    } else {
                        noSearchMatchView
                    }
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

            if let toast = vm.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Theme.serifBold(13))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(gold.opacity(0.4), lineWidth: 1)
                                )
                        )
                        .padding(.bottom, 40)
                        .accessibilityLabel(toast)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.25), value: vm.toastMessage)
        .task {
            await vm.start()
        }
        .onAppear {
            if vm.connected { Task { await vm.reload() } }
        }
        .onChange(of: vm.toastMessage) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                vm.toastMessage = nil
            }
        }
        .onDisappear {
            vm.teardown()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            Text("GALLERY")
                .font(Theme.serifBold(28))
                .tracking(4)
                .foregroundStyle(gold)
                .shadow(color: gold.opacity(0.3), radius: 10)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, gold.opacity(0.55), .clear],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 100, height: 1)
            Text("community creations")
                .font(Theme.serifItalic(13))
                .foregroundStyle(Theme.textTertiary)
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
            .font(Theme.serif(11))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.bottom, 8)
    }

    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(GalleryViewModel.Filter.allCases, id: \.self) { f in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        vm.filter = f
                    }
                } label: {
                    Text(f.label)
                        .font(Theme.serifBold(11))
                        .tracking(2)
                        .foregroundStyle(vm.filter == f ? bg : Color.white.opacity(0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(vm.filter == f
                                    ? AnyShapeStyle(LinearGradient(
                                        colors: [
                                            Theme.goldBright,
                                            Theme.goldDeep
                                        ],
                                        startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Color.white.opacity(0.05)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(vm.filter == f
                                    ? Color.white.opacity(0.25)
                                    : Color.white.opacity(0.1),
                                    lineWidth: 0.8)
                        )
                        .shadow(color: vm.filter == f ? gold.opacity(0.4) : .clear,
                                radius: 8, y: 3)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        TextField("Search samples", text: $vm.searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(Theme.serif(14))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 12)
            .accessibilityLabel("Search samples")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(message)
                .font(Theme.serif(13))
                .foregroundStyle(Theme.errorText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("RETRY") {
                Task { await vm.reload() }
            }
            .font(Theme.serifBold(12))
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
                .font(Theme.serifBold(16))
                .foregroundStyle(gold)
            Text("No community creations published yet — be the first.")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    private var noSearchMatchView: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No matches")
                .font(Theme.serifBold(16))
                .foregroundStyle(gold)
            Text("No samples match “\(vm.searchText)”")
                .font(Theme.serif(12))
                .foregroundStyle(Theme.textTertiary)
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
                        .font(Theme.serifBold(14))
                        .foregroundStyle(cream)
                        .lineLimit(1)
                    if equipped {
                        Text("EQUIPPED")
                            .font(Theme.serifBold(8))
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
                        .font(Theme.serifBold(9))
                        .tracking(1.5)
                        .foregroundStyle(typeColor(asset))
                }
                Text("by \(asset.creatorId.prefix(8))")
                    .font(Theme.serif(10))
                    .foregroundStyle(Theme.textTertiary)
                subtitleLine(for: asset)
            }

            Spacer()

            Button {
                Task { await vm.use(asset) }
            } label: {
                Text(equipped ? "USING" : "USE")
                    .font(Theme.serifBold(10))
                    .tracking(2)
                    .foregroundStyle(equipped ? bg : gold)
                    .frame(width: 76, height: 28)
                    .background(equipped ? gold : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(gold.opacity(equipped ? 0 : 0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 76, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(equipped ? "Unequip \(asset.title)" : "Equip \(asset.title)")
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(vm.previewingId == asset.id ? "Stop preview" : "Preview sound")
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
                    .font(Theme.serif(10))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .music:
            if let meta = asset.decodeMusicMetadata() {
                Text(formatAssetDuration(meta.duration_ms))
                    .font(Theme.serif(10))
                    .foregroundStyle(Theme.textTertiary)
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

        var assetType: AssetType? {
            switch self {
            case .all:   return nil
            case .piece: return .piece
            case .sfx:   return .sfx
            case .music: return .music
            }
        }
    }

    @Published var assets: [Asset] = []
    @Published var loading: Bool = true
    @Published var connecting: Bool = true
    @Published var connected: Bool = false
    @Published var errorMessage: String?
    @Published var filter: Filter = .all
    @Published var searchText: String = ""
    @Published var previewingId: String?
    @Published var toastMessage: String?

    let client: SocketClient
    private var previewPlayer: AVAudioPlayer?

    init() {
        self.client = SocketClient()
    }

    var filteredAssets: [Asset] {
        filterAssets(assets, type: filter.assetType, search: searchText)
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
        objectWillChange.send()
        if wasEquipped {
            toastMessage = "Removed from your game"
        } else if let slot = replacedSlot {
            toastMessage = "Replaced your \(slot) sound"
        } else {
            toastMessage = "Added to your game"
        }
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
