// InsightsView.swift
// GitHub-style streak and word stats. Three layers:
//   1. Hero band — 3 stat tiles on a deep-green section band
//   2. Streak heatmap — 7 columns × N weeks, cells colored by activity
//   3. Trend line — last 30 days, words/day
//   4. Language breakdown — horizontal bars

import SwiftUI

struct InsightsView: View {

    @EnvironmentObject private var statsObserver: StatsObserver

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDSpacing.xxl.rawValue) {
                heroStats
                streakHeatmap
                trendLine
                languageBreakdown
            }
            .padding(HDSpacing.xxl.rawValue)
            .frame(maxWidth: .infinity)
        }
        .background(HDColor.canvas)
    }

    // MARK: - Hero stats

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("INSIGHTS")
                    .font(HDFont.monoLabel(size: 12))
                    .hdTracking(0.5)
                    .foregroundStyle(HDColor.muted)
                Text("Как много ты сказал")
                    .font(HDFont.cardHeading)
                    .hdTracking(-0.32)
                    .foregroundStyle(HDColor.ink)
            }

            HDSectionBand(cornerRadius: .lg, padding: .xl) {
                HStack(alignment: .top, spacing: HDSpacing.xl.rawValue) {
                    HDStatTile(
                        label: "Всего слов",
                        value: formattedNumber(statsObserver.stats.totalWords),
                        surface: .dark
                    )
                    HDStatTile(
                        label: "Всего символов",
                        value: formattedNumber(statsObserver.stats.totalChars),
                        surface: .dark
                    )
                    HDStatTile(
                        label: "Текущая серия",
                        value: "\(statsObserver.stats.currentStreak) \(dayWord(statsObserver.stats.currentStreak))",
                        delta: "макс \(statsObserver.stats.longestStreak)",
                        surface: .dark
                    )
                }
            }
        }
    }

    private func dayWord(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "дней" }
        switch mod10 {
        case 1: return "день"
        case 2, 3, 4: return "дня"
        default: return "дней"
        }
    }

    // MARK: - Streak heatmap

    private var streakHeatmap: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            Text("Streak")
                .font(HDFont.featureHeading)
                .foregroundStyle(HDColor.ink)
            Text("Последние 26 недель активности")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)

            StreakHeatmapView(
                last30Days: statsObserver.stats.last30Days,
                calendar: .current
            )
            .frame(height: 140)
        }
    }

    // MARK: - Trend line

    private var trendLine: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            Text("Динамика")
                .font(HDFont.featureHeading)
                .foregroundStyle(HDColor.ink)
            Text("Слов в день за последние 30 дней")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)

            TrendLineView(values: statsObserver.stats.last30Days)
                .frame(height: 140)
                .padding(HDSpacing.lg.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                        .fill(HDColor.softStone)
                )
        }
    }

    // MARK: - Language breakdown

    private var languageBreakdown: some View {
        let byLang = statsObserver.stats.byLanguage
        let maxVal = byLang.values.max() ?? 1

        return VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            Text("Языки")
                .font(HDFont.featureHeading)
                .foregroundStyle(HDColor.ink)
            Text("Распределение слов по языкам")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)

            if byLang.isEmpty {
                Text("Пока нет данных")
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.muted)
            } else {
                VStack(spacing: HDSpacing.sm.rawValue) {
                    ForEach(byLang.sorted(by: { $0.value > $1.value }), id: \.key) { lang, words in
                        LanguageRow(language: lang, words: words, maxWords: maxVal)
                    }
                }
                .padding(HDSpacing.lg.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                        .fill(HDColor.softStone)
                )
            }
        }
    }

    // MARK: - Helpers

    private func formattedNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Heatmap view

private struct StreakHeatmapView: View {

    let last30Days: [Int]      // 0/1 per day for the last 30 days
    let calendar: Calendar

    private let weeksToShow = 26

    var body: some View {
        let grid = buildGrid()
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<grid.count, id: \.self) { weekIdx in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { dayIdx in
                                let val = grid[weekIdx][dayIdx]
                                cell(value: val)
                            }
                        }
                    }
                }
                HStack {
                    Text("Меньше")
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                    ForEach(0..<5, id: \.self) { i in
                        cell(value: i)
                    }
                    Text("Больше")
                        .font(HDFont.micro)
                        .foregroundStyle(HDColor.muted)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func cell(value: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorFor(value: value))
            .frame(width: 14, height: 14)
    }

    private func colorFor(value: Int) -> Color {
        switch value {
        case 0: return HDColor.borderLight
        case 1: return HDColor.paleGreen
        case 2: return HDColor.coralSoft
        case 3: return HDColor.coral
        default: return HDColor.deepGreen
        }
    }

    /// Build a `weeksToShow × 7` grid of activity values. We only have
    /// 30 days of truth from stats; for older cells we extrapolate as 0.
    private func buildGrid() -> [[Int]] {
        var grid: [[Int]] = []
        let recent = Array(last30Days.suffix(weeksToShow * 7))

        // Pad to weeksToShow * 7 if we have less data.
        var padded = recent
        while padded.count < weeksToShow * 7 {
            padded.insert(0, at: 0)
        }

        for weekIdx in 0..<weeksToShow {
            var week: [Int] = []
            for dayIdx in 0..<7 {
                let idx = weekIdx * 7 + dayIdx
                week.append(idx < padded.count ? padded[idx] : 0)
            }
            grid.append(week)
        }
        return grid
    }
}

// MARK: - Trend line

private struct TrendLineView: View {

    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 0, 1)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let path = Path { p in
                guard !values.isEmpty else { return }
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height - (CGFloat(v) / CGFloat(maxV)) * geo.size.height
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                path
                    .stroke(HDColor.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = values.last, values.count > 0 {
                    let x = CGFloat(values.count - 1) * stepX
                    let y = geo.size.height - (CGFloat(last) / CGFloat(maxV)) * geo.size.height
                    Circle()
                        .fill(HDColor.coral)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - Language row

private struct LanguageRow: View {

    let language: String
    let words: Int
    let maxWords: Int

    private var languageName: String {
        switch language {
        case "ru":   return "Русский"
        case "en":   return "English"
        case "auto": return "Авто"
        default:     return language
        }
    }

    var body: some View {
        HStack(spacing: HDSpacing.md.rawValue) {
            Text(languageName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HDColor.ink)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(HDColor.borderLight)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(HDColor.coral)
                        .frame(width: geo.size.width * CGFloat(words) / CGFloat(max(maxWords, 1)), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(words)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HDColor.muted)
                .frame(width: 80, alignment: .trailing)
        }
        .frame(height: 24)
    }
}