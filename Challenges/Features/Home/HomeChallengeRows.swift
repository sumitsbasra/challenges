import SwiftUI

// MARK: - Active Challenge Row (rank + points)

struct ActiveChallengeRow: View {
    let item: TodayItem

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.challenge.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("+\(Int(item.todayPoints)) pts today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(item.daysRemainingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                rankBadge
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.trailing, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rankBadge: some View {
        Group {
            switch item.rank {
            case 1:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankGold)
            case 2:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankSilver)
            case 3:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankBronze)
            default:
                Text("#\(item.rank)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pending / Completed Challenge Row

struct PendingChallengeRow: View {
    let challenge: Challenge
    var rank: Int? = nil
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Title + date
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 8)

            // Right badge + chevron
            HStack(spacing: 8) {
                rightBadge
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.trailing, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(dimmed ? 0.65 : 1)
    }

    @ViewBuilder
    private var rightBadge: some View {
        switch challenge.status {
        case .pending:
            Text(challenge.startCountdownText())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.stepsColor)
        case .completed:
            if let r = rank {
                switch r {
                case 1:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankGold)
                case 2:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankSilver)
                case 3:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankBronze)
                default:
                    Text("#\(r)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .active:
            EmptyView()
        }
    }

    private var dateRange: String {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let startYear = cal.component(.year, from: challenge.startDate)
        let endYear   = cal.component(.year, from: challenge.endDate)

        let start = challenge.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end: String
        if endYear != thisYear || startYear != endYear {
            end = challenge.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        } else {
            end = challenge.endDate.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(start) – \(end)"
    }

}

// MARK: - Challenge Card Previews

#Preview("Challenge Cards") {
    ZStack {
        Color.appBackground.ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                // ── Active ────────────────────────────────────────────
                cardGroup(title: "Active") {
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 1, today: 420,  total: 3_200, daysLeft: 4))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 2, today: 190,  total: 2_810, daysLeft: 4))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 3, today: 0,    total: 2_390, daysLeft: 1))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 5, today: 305,  total: 1_540, daysLeft: 6))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 8, today: 0,    total: 0,     daysLeft: 0))
                }

                // ── Upcoming ──────────────────────────────────────────
                cardGroup(title: "Upcoming") {
                    PendingChallengeRow(challenge: CardPreviewData.pending1)
                    PendingChallengeRow(challenge: CardPreviewData.pending2)
                    PendingChallengeRow(challenge: CardPreviewData.pending3)
                }

                // ── Completed ─────────────────────────────────────────
                cardGroup(title: "Completed") {
                    PendingChallengeRow(challenge: CardPreviewData.completed1, rank: 1, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed2, rank: 2, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed3, rank: 3, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed4, rank: 5, dimmed: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }
    .navigationTitle("Saturday, Mar 21")
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func cardGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.fitnessHeader())
            .padding(.horizontal, 4)
        content()
    }
}

private enum CardPreviewData {
    static let cal = Calendar.current
    static let now = Date()

    static func date(adding days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: now)!
    }

    static func challenge(title: String, status: ChallengeStatus, start: Date, end: Date) -> Challenge {
        Challenge(id: UUID().uuidString, title: title, creatorID: "me",
                  startDate: start, endDate: end, status: status,
                  inviteCode: "ABC123", createdAt: now)
    }

    static func active1Item(rank: Int, today: Double, total: Double, daysLeft: Int) -> TodayItem {
        let end = date(adding: daysLeft)
        let c = challenge(title: "Summer Step Challenge", status: .active,
                          start: date(adding: -7), end: end)
        return TodayItem(id: c.id, challenge: c, rank: rank,
                         participantCount: 8, todayPoints: today, totalPoints: total)
    }

    // Active challenges (different instances so NavigationLink values are unique)
    static let active1 = challenge(title: "Summer Step Challenge", status: .active, start: date(adding: -7), end: date(adding: 4))
    static let active2 = challenge(title: "Spring Fitness Blitz",  status: .active, start: date(adding: -3), end: date(adding: 4))
    static let active3 = challenge(title: "Office Challenge",      status: .active, start: date(adding: -6), end: date(adding: 1))
    static let active4 = challenge(title: "Monthly Move Goals",    status: .active, start: date(adding: -1), end: date(adding: 6))
    static let active5 = challenge(title: "Quick Sprint",          status: .active, start: date(adding: -7), end: date(adding: 0))

    // Upcoming
    static let pending1 = challenge(title: "Weekend Warrior",      status: .pending, start: date(adding: 1),  end: date(adding: 8))
    static let pending2 = challenge(title: "April Steps",          status: .pending, start: date(adding: 7),  end: date(adding: 14))
    static let pending3 = challenge(title: "New Year Kickoff",     status: .pending, start: date(adding: 285), end: date(adding: 292))

    // Completed
    static let completed1 = challenge(title: "March Madness",     status: .completed, start: date(adding: -14), end: date(adding: -7))
    static let completed2 = challenge(title: "Valentine's Run",   status: .completed, start: date(adding: -35), end: date(adding: -28))
    static let completed3 = challenge(title: "Winter Steps",      status: .completed, start: date(adding: -60), end: date(adding: -53))
    static let completed4 = challenge(title: "New Year Challenge", status: .completed, start: date(adding: -90), end: date(adding: -83))
}

// MARK: - Metric Row

struct HomeMetricRow: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Label always grey
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            // Number line: "457/700 CAL" — all ring color, unit smaller
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(current).formatted())/\(Int(goal).formatted())")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .tracking(0.3)
            }
        }
    }
}

// MARK: - Mock Data (Debug only)
