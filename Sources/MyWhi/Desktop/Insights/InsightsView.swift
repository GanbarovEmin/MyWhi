// InsightsView.swift
// GitHub-style streak and word stats. Three layers:
//   1. Hero band — 3 stat tiles on a deep-green section band
//   2. Streak heatmap — 7 columns × N weeks, cells colored by activity
//   3. Trend line — last 30 days, words/day
//   4. Language breakdown — horizontal bars
//
// Phase 7: HDTheme migration, hardcoded fonts → HDFont tokens.
//   Performance: heatmap grid is now cached in @State and only rebuilt
//   when last30Days actually changes.

import SwiftUI

struct InsightsView: View {

    @EnvironmentObject private var statsObserver: StatsObserver
    @Environment(\.hdTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDSpacing.xxl.rawValue) {
                if statsObserver.notes.isEmpty {
                    insightsEmpty
                } else {
                    heroStats
                    streakHeatmap
                    trendLine
                    languageBreakdown
                }
            }
            .padding(HDSpacing.xxl.rawValue)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .task {
            await statsObserver.refresh()
        }
    }

    /// Onboarding empty state — when there are no notes, we show a
    /// friendly call-to-action instead of zeros (audit #19).
    ///
    /// Phase 9: subtle fade-in + scale transition so empty states feel
    /// intentional, not jarring.
    private var insightsEmpty: some View {
        VStack(spacing: HDSpacing.lg.rawValue) {
            Image(systemName: "chart.bar.xaxis")
                .font(HDFont.emptyHero)
                .foregroundStyle(theme.muted)
            VStack(spacing: HDSpacing.xs.rawValue) {
                Text("Пока пусто")
                    .font(HDFont.cardHeading)
                    .foregroundStyle(theme.ink)
                Text("Запиши первую фразу на вкладке «Запись» —\nи здесь появятся твои слова, серии и streak heatmap.")
                    .font(HDFont.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(HDSpacing.xxl.rawValue)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Hero stats

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("INSIGHTS")
                    .font(HDFont.monoLabel(size: 12))
                    .hdTracking(0.5)
                    .foregroundStyle(theme.muted)
                Text("Как много ты сказал")
                    .font(HDFont.cardHeading)
                    .hdTracking(-0.32)
                    .foregroundStyle(theme.ink)
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
                .foregroundStyle(theme.ink)
            Text("Последние 26 недель активности")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)

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
                .foregroundStyle(theme.ink)
            Text("Слов в день за последние 30 дней")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)

            TrendLineView(values: statsObserver.stats.last30Days)
                .frame(height: 140)
                .padding(HDSpacing.lg.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                        .fill(theme.surfaceStone)
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
                .foregroundStyle(theme.ink)
            Text("Распределение слов по языкам")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)

            if byLang.isEmpty {
                Text("Пока нет данных")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            } else {
                VStack(spacing: HDSpacing.sm.rawValue) {
                    ForEach(byLang.sorted(by: { $0.value > $1.value }), id: \.key) { lang, words in
                        LanguageRow(language: lang, words: words, maxWords: maxVal)
                    }
                }
                .padding(HDSpacing.lg.rawValue)
                .background(
                    RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                        .fill(theme.surfaceStone)
                )
            }
        }
    }

    // MARK: - Helpers

    private func formattedNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Heatmap view

private struct StreakHeatmapView: View {

    let last30Days: [Int]      // 0/1 per day for the last 30 days
    let calendar: Calendar

    private let weeksToShow = 26

    @Environment(\.hdTheme) private var theme

    // Cache the grid. Recompute only when the data changes.
    @State private var gridCache: [[Int]] = []
    @State private var lastCacheKey: String = ""

    var body: some View {
        let grid = ensureCache()
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
                        .foregroundStyle(theme.muted)
                    ForEach(0..<5, id: \.self) { i in
                        cell(value: i)
                    }
                    Text("Больше")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Build or reuse the cached grid based on a stable key derived from
    /// the input data. ~26 weeks * 7 days = 182 cells — small, but the
    /// old code rebuilt the array on every parent re-render.
    private func ensureCache() -> [[Int]] {
        let key = last30Days.map(String.init).joined(separator: ",")
        if key != lastCacheKey {
            gridCache = buildGrid()
            lastCacheKey = key
        }
        return gridCache
    }

    private func cell(value: Int) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorFor(value: value))
            .frame(width: 14, height: 14)
    }

    private func colorFor(value: Int) -> Color {
        switch value {
        case 0: return theme.border
        case 1: return theme.surfacePaleGreen
        case 2: return theme.coralSoft
        case 3: return theme.coral
        default: return theme.deepGreen
        }
    }

    /// Build a `weeksToShow × 7` grid of activity values. We only have
    /// 30 days of truth from stats; for older cells we extrapolate as 0.
    private func buildGrid() -> [[Int]] {
        var grid: [[Int]] = []
        let recent = Array(last30Days.suffix(weeksToShow * 7))

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

    @Environment(\.hdTheme) private var theme

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
                    .stroke(theme.coral, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = values.last, values.count > 0 {
                    let x = CGFloat(values.count - 1) * stepX
                    let y = geo.size.height - (CGFloat(last) / CGFloat(maxV)) * geo.size.height
                    Circle()
                        .fill(theme.coral)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// MARK: - Language row

private struct LanguageRow: View {

    @Environment(\.hdTheme) private var theme

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
                .font(HDFont.formLabel)
                .foregroundStyle(theme.ink)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.border)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.coral)
                        .frame(width: geo.size.width * CGFloat(words) / CGFloat(max(maxWords, 1)), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(words)")
                .font(HDFont.noteMeta)
                .foregroundStyle(theme.muted)
                .frame(width: 80, alignment: .trailing)
        }
        .frame(height: 24)
    }
}
