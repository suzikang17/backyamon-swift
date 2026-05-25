import SwiftUI

struct HomeView: View {
    @State private var showDifficulty = false
    @State private var showLobby = false
    @State private var showProfile = false
    @State private var showCustomize = false

    private let bg = Color(red: 0.08, green: 0.12, blue: 0.08)
    private let gold = Color(red: 0.85, green: 0.72, blue: 0.45)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                VStack(spacing: 48) {
                    VStack(spacing: 8) {
                        Text("BACKYAMON")
                            .font(.custom("Georgia-Bold", size: 42))
                            .foregroundStyle(.white)
                            .tracking(6)

                        Text("backgammon on the beach")
                            .font(.custom("Georgia", size: 16))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .tracking(2)
                    }

                    VStack(spacing: 16) {
                        Button {
                            showDifficulty = true
                        } label: {
                            Text("PLAY")
                                .font(.custom("Georgia-Bold", size: 20))
                                .tracking(4)
                                .foregroundStyle(bg)
                                .frame(width: 220, height: 52)
                                .background(gold)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Button {
                            showLobby = true
                        } label: {
                            Text("PLAY ONLINE")
                                .font(.custom("Georgia-Bold", size: 18))
                                .tracking(4)
                                .foregroundStyle(.white)
                                .frame(width: 220, height: 52)
                                .background(Color(red: 0.0, green: 0.42, blue: 0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Button {
                            showCustomize = true
                        } label: {
                            Text("CUSTOMIZE")
                                .font(.custom("Georgia-Bold", size: 16))
                                .tracking(4)
                                .foregroundStyle(gold)
                                .frame(width: 220, height: 44)
                                .background(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(gold.opacity(0.45), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                // Profile icon in the top-right corner.
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showProfile = true
                        } label: {
                            Image(systemName: "person.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(gold)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
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
