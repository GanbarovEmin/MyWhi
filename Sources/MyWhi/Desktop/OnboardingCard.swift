// OnboardingCard.swift
// Shown on the Home view when the vault is empty. Tells the user how
// to start. The "Big button" reference hints at the hero record control.
//
// Phase 7: HDTheme migration. Phase 7.13: auto-dismiss after first
// successful recording (controlled by `mywhi.hideOnboarding` AppStorage).

import SwiftUI

struct OnboardingCard: View {

    @Environment(\.hdTheme) private var theme
    @AppStorage("mywhi.hideOnboarding") private var hideOnboarding: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            HStack(spacing: HDSpacing.sm.rawValue) {
                Image(systemName: "hand.wave.fill")
                    .font(HDFont.waveIcon)
                    .foregroundStyle(theme.coral)
                Text("Привет!")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(theme.ink)
            }
            Text("Нажми большую кнопку выше, чтобы записать первую фразу. После остановки записи MyWhi транскрибирует её локально и скопирует в буфер.")
                .font(HDFont.body)
                .foregroundStyle(theme.ink)
            HStack(spacing: HDSpacing.xs.rawValue) {
                Image(systemName: "keyboard")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(theme.muted)
                Text("⌘⌥D — начать запись из любого приложения")
                    .font(HDFont.caption)
                    .foregroundStyle(theme.muted)
            }

            Toggle("Больше не показывать", isOn: $hideOnboarding)
                .toggleStyle(.checkbox)
                .font(HDFont.caption)
        }
        .padding(HDSpacing.xl.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                .fill(theme.surfacePaleGreen)
        )
    }
}