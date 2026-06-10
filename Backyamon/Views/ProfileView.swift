import SwiftUI

/// Navigation target for viewing a player's profile.
struct PlayerProfileDestination: Hashable {
    let username: String
}

/// Player profile screen. Same view is used for "my profile" and
/// "other player's profile" — parameterized by `username`.
struct ProfileView: View {
    @StateObject private var vm: ProfileViewModel

    private let bg = Theme.bg
    private let gold = Theme.gold
    private let red = Theme.red
    private let cream = Theme.cream

    init(username: String, client: SocketClient) {
        _vm = StateObject(wrappedValue: ProfileViewModel(username: username, client: client))
    }

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
                    .font(Theme.serifBold(32))
                    .foregroundStyle(gold)
            }

            VStack(spacing: 4) {
                Text(vm.profile?.username ?? vm.username)
                    .font(Theme.serifBold(26))
                    .foregroundStyle(.white)
                    .tracking(2)
                if let prof = vm.profile {
                    Text("\(prof.wins) – \(prof.losses)")
                        .font(Theme.serif(14))
                        .foregroundStyle(Theme.textTertiary)
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
                .font(Theme.serifBold(26))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.3), radius: 6)
            Text(label)
                .font(Theme.serifBold(10))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
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
                .font(Theme.serifBold(10))
                .tracking(3)
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 8) {
                winTypeCard(label: "YA MON", count: profile.yaMonWins, tint: gold.opacity(0.8))
                winTypeCard(label: "BIG YA MON", count: profile.bigYaMonWins, tint: gold)
                winTypeCard(label: "MASSIVE", count: profile.massiveYaMonWins, tint: Theme.green)
            }
        }
    }

    private func winTypeCard(label: String, count: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(Theme.serifBold(20))
                .foregroundStyle(tint)
            Text(label)
                .font(Theme.serifBold(9))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
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
                .font(Theme.serifBold(10))
                .tracking(3)
                .foregroundStyle(Theme.textTertiary)

            if profile.recentMatches.isEmpty {
                Text("No matches played yet.")
                    .font(Theme.serif(13))
                    .foregroundStyle(Theme.textTertiary)
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
                .font(Theme.serifBold(12))
                .foregroundStyle(match.isWin ? gold : red)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill((match.isWin ? gold : red).opacity(0.15))
                )

            // vs opponent (tappable)
            NavigationLink(value: PlayerProfileDestination(username: match.opponent)) {
                HStack(spacing: 4) {
                    Text("vs")
                        .font(Theme.serif(12))
                        .foregroundStyle(Theme.textTertiary)
                    Text(match.opponent)
                        .font(Theme.serifBold(13))
                        .foregroundStyle(gold)
                }
            }

            Spacer()

            // win type
            Text(formatWinType(match.winType))
                .font(Theme.serifBold(9))
                .tracking(1)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            Text(timeAgo(match.completedAt))
                .font(Theme.serif(10))
                .foregroundStyle(Theme.textTertiary)
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
                .font(Theme.serif(14))
                .foregroundStyle(Theme.errorText)
                .multilineTextAlignment(.center)
            Button {
                Task { await vm.load() }
            } label: {
                Text("RETRY")
                    .font(Theme.serifBold(12))
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
