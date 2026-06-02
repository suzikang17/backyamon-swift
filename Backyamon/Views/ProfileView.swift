import SwiftUI

/// Navigation target for viewing a player's profile.
struct PlayerProfileDestination: Hashable {
    let username: String
}

/// Player profile screen. Same view is used for "my profile" and
/// "other player's profile" — parameterized by `username`.
struct ProfileView: View {
    @StateObject private var vm: ProfileViewModel

    private let bg = Color(red: 0.08, green: 0.12, blue: 0.08)
    private let gold = Color(red: 0.85, green: 0.72, blue: 0.45)
    private let red = Color(red: 0.7, green: 0.2, blue: 0.2)
    private let cream = Color(red: 0.96, green: 0.94, blue: 0.88)

    init(username: String, client: SocketClient) {
        _vm = StateObject(wrappedValue: ProfileViewModel(username: username, client: client))
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.14, green: 0.22, blue: 0.15),
                    Color(red: 0.05, green: 0.09, blue: 0.06)
                ],
                center: .top,
                startRadius: 80,
                endRadius: 600
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerView

                    if vm.loading {
                        ProgressView()
                            .tint(gold)
                            .padding(.top, 40)
                    } else if let err = vm.errorMessage {
                        errorView(err)
                    } else if let profile = vm.profile {
                        statsRow(profile: profile)
                        winTypeBreakdown(profile: profile)
                        recentMatchesList(profile: profile)
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlayerProfileDestination.self) { dest in
            ProfileView(username: dest.username, client: vm.client)
        }
        .task {
            await vm.load()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gold.opacity(0.3), gold.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(gold.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: gold.opacity(0.35), radius: 12)
                Text(String((vm.profile?.username ?? vm.username).prefix(1)).uppercased())
                    .font(.custom("Georgia-Bold", size: 32))
                    .foregroundStyle(gold)
            }

            VStack(spacing: 4) {
                Text(vm.profile?.username ?? vm.username)
                    .font(.custom("Georgia-Bold", size: 26))
                    .foregroundStyle(.white)
                    .tracking(2)
                if let prof = vm.profile {
                    Text("\(prof.wins) – \(prof.losses)")
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .tracking(2)
                }
            }
        }
        .padding(.top, 12)
    }

    private func statsRow(profile: PlayerProfile) -> some View {
        HStack(spacing: 12) {
            statCard(label: "WINS", value: "\(profile.wins)", color: gold)
            statCard(label: "LOSSES", value: "\(profile.losses)", color: red)
            statCard(
                label: "WIN %",
                value: profile.totalGames > 0 ? "\(profile.winPct)%" : "—",
                color: .white
            )
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.custom("Georgia-Bold", size: 26))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.3), radius: 6)
            Text(label)
                .font(.custom("Georgia-Bold", size: 10))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        )
    }

    private func winTypeBreakdown(profile: PlayerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WIN TYPES")
                .font(.custom("Georgia-Bold", size: 10))
                .tracking(3)
                .foregroundStyle(Color.white.opacity(0.5))

            HStack(spacing: 8) {
                winTypeCard(label: "YA MON", count: profile.yaMonWins, tint: gold.opacity(0.8))
                winTypeCard(label: "BIG YA MON", count: profile.bigYaMonWins, tint: gold)
                winTypeCard(label: "MASSIVE", count: profile.massiveYaMonWins, tint: Color(red: 0.0, green: 0.55, blue: 0.32))
            }
        }
    }

    private func winTypeCard(label: String, count: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.custom("Georgia-Bold", size: 20))
                .foregroundStyle(tint)
            Text(label)
                .font(.custom("Georgia-Bold", size: 9))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func recentMatchesList(profile: PlayerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT MATCHES")
                .font(.custom("Georgia-Bold", size: 10))
                .tracking(3)
                .foregroundStyle(Color.white.opacity(0.5))

            if profile.recentMatches.isEmpty {
                Text("No matches played yet.")
                    .font(.custom("Georgia", size: 13))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                ForEach(profile.recentMatches) { match in
                    matchRow(match)
                }
            }
        }
    }

    private func matchRow(_ match: RecentMatch) -> some View {
        HStack(spacing: 10) {
            // W/L badge
            Text(match.isWin ? "W" : "L")
                .font(.custom("Georgia-Bold", size: 12))
                .foregroundStyle(match.isWin ? gold : red)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill((match.isWin ? gold : red).opacity(0.15))
                )

            // vs opponent (tappable)
            NavigationLink(value: PlayerProfileDestination(username: match.opponent)) {
                HStack(spacing: 4) {
                    Text("vs")
                        .font(.custom("Georgia", size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text(match.opponent)
                        .font(.custom("Georgia-Bold", size: 13))
                        .foregroundStyle(gold)
                }
            }

            Spacer()

            // win type
            Text(formatWinType(match.winType))
                .font(.custom("Georgia-Bold", size: 9))
                .tracking(1)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Text(timeAgo(match.completedAt))
                .font(.custom("Georgia", size: 10))
                .foregroundStyle(Color.white.opacity(0.35))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.custom("Georgia", size: 14))
                .foregroundStyle(red)
                .multilineTextAlignment(.center)
            Button {
                Task { await vm.load() }
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
        .padding(.top, 40)
    }
}
