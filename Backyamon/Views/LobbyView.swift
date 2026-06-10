import SwiftUI

/// Online lobby: connect, register, claim username, quick match, create/join rooms.
@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var connected = false
    @Published var connecting = true
    @Published var displayName = ""
    @Published var username: String? = nil
    @Published var rooms: [WaitingRoom] = []
    @Published var players: [LeaderboardPlayer] = []
    @Published var recentMatches: [LobbyRecentMatch] = []
    @Published var connectionError: String? = nil
    @Published var lobbyError: String? = nil
    @Published var roomCode: String? = nil
    @Published var searching = false

    /// Set by the view when the server reports a match. Triggers navigation.
    @Published var activeRoomId: String? = nil

    let client: SocketClient

    private var matchFoundToken: UUID?
    private var roomJoinedToken: UUID?
    private var roomListToken: UUID?
    private var playerListToken: UUID?
    private var errorToken: UUID?

    init() {
        self.client = SocketClient()
    }

    init(client: SocketClient) {
        self.client = client
    }

    func start() async {
        connecting = true
        connectionError = nil

        client.onConnect = { [weak self] in
            Task { @MainActor in self?.connected = true }
        }
        client.onDisconnect = { [weak self] in
            Task { @MainActor in self?.connected = false }
        }
        client.onReconnect = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                _ = try? await self.client.register()
            }
        }

        do {
            try await client.connect(maxRetries: 5) { _, _ in }
            connected = true
            let identity = try await client.register()
            displayName = identity.displayName
            username = identity.username
            bindLobbyEvents()
            client.listRooms()
            client.listPlayers()
            await refreshRecentMatches()
        } catch {
            connectionError = error.localizedDescription
        }
        connecting = false
    }

    /// Re-fetch the lobby recent-matches feed.
    func refreshRecentMatches() async {
        do {
            let matches = try await client.getRecentMatches(limit: 10)
            recentMatches = matches
        } catch {
            // Non-fatal; just keep the previous list.
        }
    }

    func tearDown() {
        unbindLobbyEvents()
        if searching { client.leaveQueue() }
        client.disconnect()
    }

    func retryConnect() {
        Task { await start() }
    }

    func claimUsername(_ input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let claimed = try await client.claimUsername(trimmed)
            username = claimed
            displayName = claimed
            client.listPlayers()
        } catch {
            lobbyError = error.localizedDescription
        }
    }

    func quickMatch() {
        lobbyError = nil
        searching = true
        client.quickMatch()
    }

    func cancelQuickMatch() {
        client.leaveQueue()
        searching = false
    }

    func createRoom(name: String) async {
        lobbyError = nil
        do {
            let code = try await client.createRoom(name: name)
            roomCode = code
        } catch {
            lobbyError = error.localizedDescription
        }
    }

    func joinRoom(_ id: String) async {
        lobbyError = nil
        do {
            try await client.joinRoom(id)
            // navigation triggers via room-joined handler
        } catch {
            lobbyError = error.localizedDescription
        }
    }

    func cancelRoom() {
        if let code = roomCode {
            client.leaveRoom(code)
        }
        roomCode = nil
    }

    // MARK: - Event bindings

    private func bindLobbyEvents() {
        unbindLobbyEvents()

        matchFoundToken = client.on("match-found") { [weak self] data in
            Task { @MainActor in
                guard let dict = data.first as? [String: Any],
                      let roomId = dict["roomId"] as? String else { return }
                self?.searching = false
                self?.activeRoomId = roomId
            }
        }
        roomJoinedToken = client.on("room-joined") { [weak self] data in
            Task { @MainActor in
                guard let dict = data.first as? [String: Any],
                      let roomId = dict["roomId"] as? String else { return }
                self?.activeRoomId = roomId
            }
        }
        roomListToken = client.on("room-list") { [weak self] data in
            Task { @MainActor in
                guard let dict = data.first as? [String: Any],
                      let arr = dict["rooms"] as? [[String: Any]] else { return }
                let parsed: [WaitingRoom] = arr.compactMap { d in
                    guard let id = d["id"] as? String,
                          let host = d["hostName"] as? String else { return nil }
                    let created = (d["createdAt"] as? String) ?? ""
                    return WaitingRoom(id: id, hostName: host, createdAt: created)
                }
                self?.rooms = parsed
            }
        }
        playerListToken = client.on("player-list") { [weak self] data in
            Task { @MainActor in
                guard let dict = data.first as? [String: Any],
                      let arr = dict["players"] as? [[String: Any]] else { return }
                let parsed: [LeaderboardPlayer] = arr.compactMap { d in
                    guard let username = d["username"] as? String else { return nil }
                    return LeaderboardPlayer(
                        username: username,
                        createdAt: d["createdAt"] as? String,
                        wins: (d["wins"] as? Int) ?? 0,
                        losses: (d["losses"] as? Int) ?? 0,
                        points: (d["points"] as? Int) ?? 0
                    )
                }
                self?.players = parsed.sorted { $0.points > $1.points }
            }
        }
        errorToken = client.on("error") { [weak self] data in
            Task { @MainActor in
                guard let dict = data.first as? [String: Any],
                      let msg = dict["message"] as? String else { return }
                self?.lobbyError = msg
                self?.searching = false
            }
        }
    }

    private func unbindLobbyEvents() {
        if let t = matchFoundToken { client.off("match-found", token: t) }
        if let t = roomJoinedToken { client.off("room-joined", token: t) }
        if let t = roomListToken { client.off("room-list", token: t) }
        if let t = playerListToken { client.off("player-list", token: t) }
        if let t = errorToken { client.off("error", token: t) }
        matchFoundToken = nil
        roomJoinedToken = nil
        roomListToken = nil
        playerListToken = nil
        errorToken = nil
    }
}

/// Navigation target representing an active online room.
struct OnlineRoomDestination: Hashable {
    let roomId: String
}

struct LobbyView: View {
    @StateObject private var vm = LobbyViewModel()
    @State private var usernameInput = ""
    @State private var roomJoinInput = ""
    @State private var customRoomName = ""
    @State private var navigationPath = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    private let bg = Theme.bg
    private let gold = Theme.gold
    private let red = Theme.red
    private let cream = Theme.cream

    var body: some View {
        // NOTE: the inner NavigationStack is deliberate. This view is itself
        // a navigationDestination of HomeView, and attaching the game/profile
        // navigationDestination modifiers to a pushed view's root sends
        // SwiftUI (iOS 18) into an infinite view-update loop that freezes the
        // main thread. The nested stack keeps destination registration on a
        // stack root, which is the configuration that works.
        NavigationStack(path: $navigationPath) {
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

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text("BACKYAMON")
                                .font(Theme.serifBold(32))
                                .foregroundStyle(.white)
                                .tracking(5)
                                .shadow(color: gold.opacity(0.3), radius: 12)
                            Rectangle()
                                .fill(LinearGradient(
                                    colors: [.clear, gold.opacity(0.6), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing))
                                .frame(width: 100, height: 1)
                            Text("ONLINE")
                                .font(Theme.serifBold(11))
                                .foregroundStyle(gold)
                                .tracking(6)
                        }
                        .padding(.top, 12)

                        // Connection status + identity
                        connectionStatusView

                        // Username section
                        usernameSection

                        if let err = vm.connectionError {
                            errorBanner(text: err, showRetry: true) {
                                vm.retryConnect()
                            }
                        } else if let err = vm.lobbyError {
                            errorBanner(text: err, showRetry: false, onRetry: {})
                        }

                        // Searching for match
                        if vm.searching {
                            searchingView
                        } else if let code = vm.roomCode {
                            waitingForOpponentView(code: code)
                        } else {
                            mainLobbyContent
                        }

                        leaderboardView

                        recentMatchesFeed

                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 20)
                }

            VStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("← BACK TO MENU")
                        .font(Theme.serifBold(12))
                        .tracking(3)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.bottom, 4)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OnlineRoomDestination.self) { dest in
            OnlineGameView(socket: vm.client, roomId: dest.roomId)
        }
        .navigationDestination(for: PlayerProfileDestination.self) { dest in
            ProfileView(username: dest.username, client: vm.client)
        }
        .onChange(of: vm.activeRoomId) { _, newValue in
            if let id = newValue {
                navigationPath.append(OnlineRoomDestination(roomId: id))
                vm.activeRoomId = nil
            }
        }
        .task {
            await vm.start()
        }
        .onDisappear {
            // Fires only when the lobby itself pops back to Home (game and
            // profile pushes happen on the inner stack, so this view stays).
            vm.tearDown()
        }
        }
    }

    // MARK: - Sub views

    private var connectionStatusView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.connected ? Color.green : (vm.connecting ? gold : red))
                .frame(width: 10, height: 10)
            Text(vm.connecting
                 ? "Connecting..."
                 : (vm.connected ? "Connected" : "Disconnected"))
                .font(Theme.serif(13))
                .foregroundStyle(Theme.textSecondary)
            if !vm.displayName.isEmpty {
                Text("as")
                    .font(Theme.serif(13))
                    .foregroundStyle(Theme.textTertiary)
                Text(vm.displayName)
                    .font(Theme.serifBold(13))
                    .foregroundStyle(gold)
            }
            Spacer(minLength: 8)
            if let username = vm.username {
                NavigationLink(value: PlayerProfileDestination(username: username)) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("MY PROFILE")
                            .font(Theme.serifBold(10))
                            .tracking(2)
                    }
                    .foregroundStyle(bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(gold)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var usernameSection: some View {
        Group {
            if vm.connected, vm.username == nil {
                VStack(spacing: 8) {
                    Text("PICK A USERNAME")
                        .font(Theme.serifBold(10))
                        .tracking(3)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 8) {
                        TextField("username", text: $usernameInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                            .font(Theme.serif(14))
                            .frame(width: 180)
                        let canClaim = !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty
                        Button {
                            Task {
                                await vm.claimUsername(usernameInput)
                                usernameInput = ""
                            }
                        } label: {
                            Text("CLAIM")
                                .font(Theme.serifBold(12))
                                .tracking(2)
                                .foregroundStyle(canClaim ? bg : Color.white.opacity(0.35))
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                                .background(canClaim ? AnyShapeStyle(gold) : AnyShapeStyle(Color.white.opacity(0.1)))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .disabled(!canClaim)
                    }
                }
            }
        }
    }

    private var mainLobbyContent: some View {
        VStack(spacing: 16) {
            Button {
                vm.quickMatch()
            } label: {
                Text("QUICK MATCH")
                    .font(Theme.serifBold(18))
                    .tracking(4)
                    .foregroundStyle(bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: vm.connected
                                ? [Theme.goldBright,
                                   Theme.goldDeep]
                                : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(vm.connected ? 0.25 : 0), lineWidth: 0.8)
                    )
                    .shadow(color: gold.opacity(vm.connected ? 0.4 : 0), radius: 12, y: 4)
            }
            .disabled(!vm.connected)

            VStack(spacing: 8) {
                Button {
                    Task { await vm.createRoom(name: customRoomName) }
                } label: {
                    Text("CREATE ROOM")
                        .font(Theme.serifBold(16))
                        .tracking(3)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: vm.connected
                                    ? [Theme.green,
                                       Color(red: 0.0, green: 0.38, blue: 0.22)]
                                    : [Color.gray.opacity(0.25), Color.gray.opacity(0.15)],
                                startPoint: .top, endPoint: .bottom)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(vm.connected ? 0.18 : 0), lineWidth: 0.8)
                        )
                        .shadow(color: Theme.green.opacity(vm.connected ? 0.4 : 0), radius: 10, y: 3)
                }
                .disabled(!vm.connected)

                TextField("optional room name", text: $customRoomName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Theme.textPrimary)
                    .font(Theme.serif(12))
                    .multilineTextAlignment(.center)
            }

            // Join room
            VStack(spacing: 8) {
                Text("JOIN ROOM")
                    .font(Theme.serifBold(10))
                    .tracking(3)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 8) {
                    TextField("room code", text: $roomJoinInput)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .font(Theme.serif(14))
                    let canJoin = vm.connected && !roomJoinInput.trimmingCharacters(in: .whitespaces).isEmpty
                    Button {
                        Task {
                            let id = roomJoinInput
                            await vm.joinRoom(id)
                            roomJoinInput = ""
                        }
                    } label: {
                        Text("JOIN")
                            .font(Theme.serifBold(12))
                            .tracking(2)
                            .foregroundStyle(canJoin ? bg : Color.white.opacity(0.35))
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(canJoin ? AnyShapeStyle(gold) : AnyShapeStyle(Color.white.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .disabled(!canJoin)
                }
            }

            // Open rooms list
            if !vm.rooms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPEN ROOMS")
                        .font(Theme.serifBold(10))
                        .tracking(3)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(vm.rooms) { room in
                        Button {
                            Task { await vm.joinRoom(room.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.id)
                                        .font(Theme.serifBold(14))
                                        .foregroundStyle(gold)
                                    Text(room.hostName)
                                        .font(Theme.serif(11))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text("JOIN →")
                                    .font(Theme.serifBold(11))
                                    .tracking(2)
                                    .foregroundStyle(Theme.greenBright)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    private var searchingView: some View {
        VStack(spacing: 16) {
            SearchingDots()
            Text("Searching for opponent...")
                .font(Theme.serif(16))
                .foregroundStyle(.white)
            Button {
                vm.cancelQuickMatch()
            } label: {
                Text("CANCEL")
                    .font(Theme.serifBold(12))
                    .tracking(3)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 24)
    }

    private func waitingForOpponentView(code: String) -> some View {
        VStack(spacing: 12) {
            Text("YOUR ROOM CODE")
                .font(Theme.serifBold(10))
                .tracking(3)
                .foregroundStyle(Theme.textTertiary)
            Text(code)
                .font(Theme.serifBold(36))
                .foregroundStyle(gold)
                .tracking(6)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(gold, lineWidth: 2)
                )
            Text("Waiting for opponent...")
                .font(Theme.serif(14))
                .foregroundStyle(Theme.textSecondary)
            Button {
                vm.cancelRoom()
            } label: {
                Text("CANCEL")
                    .font(Theme.serifBold(12))
                    .tracking(3)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 16)
    }

    private var leaderboardView: some View {
        Group {
            if !vm.players.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEADERBOARD")
                        .font(Theme.serifBold(10))
                        .tracking(3)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(Array(vm.players.prefix(10).enumerated()), id: \.element.username) { idx, p in
                        NavigationLink(value: PlayerProfileDestination(username: p.username)) {
                            HStack {
                                Text("\(idx + 1)")
                                    .font(Theme.serifBold(12))
                                    .foregroundStyle(rankColor(idx))
                                    .frame(width: 24, alignment: .leading)
                                Text(p.username)
                                    .font(Theme.serif(13))
                                    .foregroundStyle(gold)
                                Spacer()
                                Text("\(p.points) pts")
                                    .font(Theme.serifBold(12))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("\(p.wins)-\(p.losses)")
                                    .font(Theme.serif(11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentMatchesFeed: some View {
        Group {
            if !vm.recentMatches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT MATCHES")
                        .font(Theme.serifBold(10))
                        .tracking(3)
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(vm.recentMatches) { m in
                        HStack(spacing: 6) {
                            if let winner = m.winner {
                                NavigationLink(value: PlayerProfileDestination(username: winner)) {
                                    Text(winner)
                                        .font(Theme.serifBold(12))
                                        .foregroundStyle(gold)
                                }
                                .buttonStyle(.plain)
                                Text("beat")
                                    .font(Theme.serif(11))
                                    .foregroundStyle(Theme.textTertiary)
                                if let loser = m.loser {
                                    NavigationLink(value: PlayerProfileDestination(username: loser)) {
                                        Text(loser)
                                            .font(Theme.serif(12))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                            Text(formatWinType(m.winType))
                                .font(Theme.serifBold(9))
                                .tracking(1)
                                .foregroundStyle(Theme.textTertiary)
                            Text("\(m.pointsWon)pt")
                                .font(Theme.serif(10))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 28, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private func rankColor(_ idx: Int) -> Color {
        switch idx {
        case 0: return gold
        case 1: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 2: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color.white.opacity(0.4)
        }
    }

    private func errorBanner(text: String, showRetry: Bool, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(Theme.serif(13))
                .foregroundStyle(Theme.errorText)
                .multilineTextAlignment(.center)
            if showRetry {
                Button(action: onRetry) {
                    Text("TRY AGAIN")
                        .font(Theme.serifBold(12))
                        .tracking(3)
                        .foregroundStyle(bg)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(gold)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(red.opacity(0.6), lineWidth: 1)
        )
    }
}

/// Three staggered pulsing dots shown while matchmaking. Static (full
/// opacity) when Reduce Motion is on.
private struct SearchingDots: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [Theme.green, Theme.gold, Theme.red]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(colors[i])
                    .frame(width: 10, height: 10)
                    .opacity(animating ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                        value: animating
                    )
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            animating = true
        }
    }
}
