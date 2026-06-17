// OnboardingCard.swift
// Shown on the Home view when the vault is empty. Tells the user how
// to start. The "Big button" reference hints at the hero record control.

import SwiftUI

struct OnboardingCard: View {

    @AppStorage("mywhi.hideOnboarding") private var hideOnboarding: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            HStack(spacing: HDSpacing.sm.rawValue) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(HDColor.coral)
                Text("Привет!")
                    .font(HDFont.featureHeading)
                    .foregroundStyle(HDColor.ink)
            }
            Text("Нажми большую кнопку выше, чтобы записать первую фразу. После остановки записи MyWhi транскрибирует её локально и скопирует в буфер.")
                .font(HDFont.body)
                .foregroundStyle(HDColor.ink)
            HStack(spacing: HDSpacing.xs.rawValue) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundStyle(HDColor.muted)
                Text("Cmd+Shift+Скопировать в активное приложение")
                    .font(HDFont.caption)
                    .foregroundStyle(HDColor.muted)
            }

            Toggle("Больше не показывать", isOn: $hideOnboarding)
                .toggleStyle(.checkbox)
                .font(HDFont.caption)
        }
        .padding(HDSpacing.xl.rawValue)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.lg.rawValue, style: .continuous)
                .fill(HDColor.paleGreen)
        )
    }
}