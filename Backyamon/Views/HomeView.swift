import SwiftUI

struct HomeView: View {
    @State private var showDifficulty = false
    @State private var showLobby = false
    @State private var showProfile = false
    @State private var showCustomize = false

    private let bg = Color(red: 0.08, green: 0.12, blue: 0.08)
    private let gold = Color(red: 0.92, green: 0.78, blue: 0.45)

    var body: some View {
        NavigationStack {
            ZStack {
                // Atmospheric radial gradient — warm glow up top fading to deep green
                RadialGradient(
                    colors: [
                        Color(red: 0.16, green: 0.24, blue: 0.16),
                        Color(red: 0.05, green: 0.09, blue: 0.06)
                    ],
                    center: .top,
                    startRadius: 80,
                    endRadius: 600
                )
                .ignoresSafeArea()

                VStack(spacing: 56) {
                    VStack(spacing: 12) {
                        Text("BACKYAMON")
                            .font(.custom("Georgia-Bold", size: 44))
                            .foregroundStyle(.white)
                            .tracking(7)
                            .shadow(color: gold.opacity(0.35), radius: 18, y: 0)
                            .shadow(color: Color.black.opacity(0.6), radius: 2, y: 2)

                        // Hairline divider with gold accent
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.clear, gold.opacity(0.7), .clear],
                                startPoint: .leading,
                                endPoint: .trailing))
                            .frame(width: 140, height: 1)

                        Text("backgammon on the beach")
                            .font(.custom("Georgia-Italic", size: 14))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(2)
                    }

                    VStack(spacing: 14) {
                        PrimaryButton(title: "PLAY", action: { showDifficulty = true })
                        SecondaryButton(title: "PLAY ONLINE",
                                        color: Color(red: 0.0, green: 0.50, blue: 0.30),
                                        action: { showLobby = true })
                        GhostButton(title: "CUSTOMIZE", action: { showCustomize = true })
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showProfile = true
                        } label: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(gold)
                                .frame(width: 42, height: 42)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(Circle().stroke(gold.opacity(0.3), lineWidth: 1))
                                )
                                .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                    }
                    Spacer()
                }
            }
            .navigationDestination(isPresented: $showDifficulty) {
                DifficultyView()
            }
            .navigationDestination(isPresented: $showLobby) {
                LobbyView()
            }
            .navigationDestination(isPresented: $showProfile) {
                MyProfileLauncher()
            }
            .navigationDestination(isPresented: $showCustomize) {
                MyStuffView()
            }
        }
    }
}

/// Standalone entry point for "My Profile" from the home screen.
///
/// Creates its own `SocketClient`, registers, and pushes a `ProfileView`
/// for the currently-signed-in username (or a friendly placeholder if the
/// user hasn't claimed one yet).
struct MyProfileLauncher: View {
    @StateObject private var loader = MyProfileLoader()

    private let bg = Color(red: 0.08, green: 0.12, blue: 0.08)
    private let gold = Color(red: 0.85, green: 0.72, blue: 0.45)
    private let red = Color(red: 0.7, green: 0.2, blue: 0.2)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if let username = loader.username {
                ProfileView(username: username, client: loader.client)
            } else if let err = loader.errorMessage {
                VStack(spacing: 14) {
                    Text(err)
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(red)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await loader.start() }
                    } label: {
                        Text("RETRY")
                            .font(.custom("Georgia-Bold", size: 12))
                            .tracking(3)
                            .foregroundStyle(bg)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(gold)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 20)
            } else if loader.noUsername {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(gold.opacity(0.7))
                    Text("Claim a username first")
                        .font(.custom("Georgia-Bold", size: 16))
                        .foregroundStyle(.white)
                    Text("Head to the lobby and pick a name to start tracking stats.")
                        .font(.custom("Georgia", size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                ProgressView().tint(gold)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loader.start()
        }
        .onDisappear {
            loader.tearDown()
        }
    }
}

@MainActor
final class MyProfileLoader: ObservableObject {
    @Published var username: String?
    @Published var errorMessage: String?
    @Published var noUsername: Bool = false

    let client: SocketClient

    init() {
        self.client = SocketClient()
    }

    func start() async {
        errorMessage = nil
        noUsername = false
        do {
            try await client.connect(maxRetries: 5)
            let identity = try await client.register()
            if let name = identity.username {
                username = name
            } else {
                noUsername = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tearDown() {
        client.disconnect()
    }
}

// MARK: - Home buttons

private let homeBg = Color(red: 0.08, green: 0.12, blue: 0.08)
private let homeGold = Color(red: 0.92, green: 0.78, blue: 0.45)

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Georgia-Bold", size: 20))
                .tracking(5)
                .foregroundStyle(homeBg)
                .frame(width: 240, height: 56)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.85, blue: 0.52),
                            Color(red: 0.82, green: 0.65, blue: 0.32)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                )
                .shadow(color: homeGold.opacity(0.45), radius: 14, y: 4)
                .shadow(color: Color.black.opacity(0.45), radius: 3, y: 2)
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Georgia-Bold", size: 18))
                .tracking(4)
                .foregroundStyle(.white)
                .frame(width: 240, height: 52)
                .background(
                    LinearGradient(
                        colors: [color.opacity(1.0), color.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )
                .shadow(color: color.opacity(0.4), radius: 12, y: 4)
                .shadow(color: Color.black.opacity(0.45), radius: 3, y: 2)
        }
    }
}

struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Georgia-Bold", size: 15))
                .tracking(4)
                .foregroundStyle(homeGold)
                .frame(width: 240, height: 46)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(homeGold.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
