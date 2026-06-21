import SwiftUI

struct PostProcessingRulesView: View {

    @Environment(\.hdTheme) private var theme
    @StateObject private var store = PostProcessingRulesStore.shared

    @State private var showAddSheet = false
    @State private var draftPattern = ""
    @State private var draftReplacement = ""
    @State private var draftDescription = ""

    var body: some View {
        HDCard(.canvas) {
            VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
                sectionHeader

                if store.rules.isEmpty {
                    emptyState
                } else {
                    ruleList
                }

                Divider()
                    .padding(.vertical, HDSpacing.xs.rawValue)

                HStack {
                    Text("\(store.rules.filter(\.isEnabled).count)/\(store.rules.count) правил активно")
                        .font(HDFont.micro)
                        .foregroundStyle(theme.muted)
                    Spacer()
                    HDButtonSecondary(title: "Добавить правило", icon: "plus") {
                        draftPattern = ""
                        draftReplacement = ""
                        draftDescription = ""
                        showAddSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text("ПРАВИЛА ПОСТ-ОБРАБОТКИ")
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(theme.muted)
            Text("Regex-правила для очистки транскриптов")
                .font(HDFont.cardBody)
                .foregroundStyle(theme.ink)
            Text("Правила применяются к тексту после WhisperKit. Можно убирать слова-паразиты, исправлять пунктуацию и чинить фирменные названия.")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(HDFont.iconSmall)
                .foregroundStyle(theme.muted)
            Text("Нет пользовательских правил")
                .font(HDFont.caption)
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, HDSpacing.sm.rawValue)
    }

    private var ruleList: some View {
        VStack(spacing: 1) {
            ForEach(store.rules) { rule in
                ruleRow(rule)
                if rule.id != store.rules.last?.id {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .fill(theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func ruleRow(_ rule: PostProcessingRule) -> some View {
        HStack(spacing: HDSpacing.sm.rawValue) {
            Toggle("", isOn: .init(
                get: { rule.isEnabled },
                set: { _ in store.toggleRule(id: rule.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                if !rule.description.isEmpty {
                    Text(rule.description)
                        .font(HDFont.noteTitle)
                        .foregroundStyle(rule.isEnabled ? theme.ink : theme.muted)
                }
                HStack(spacing: 4) {
                    Text(rule.pattern)
                        .font(HDFont.monoLabel(size: 10))
                        .foregroundStyle(theme.muted)
                    if !rule.replacement.isEmpty {
                        Text("→")
                            .font(HDFont.micro)
                            .foregroundStyle(theme.muted)
                        Text(rule.replacement)
                            .font(HDFont.monoLabel(size: 10))
                            .foregroundStyle(theme.actionBlue)
                    }
                }
            }

            Spacer(minLength: 0)
            Button {
                store.deleteRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(HDFont.iconSmall)
                    .foregroundStyle(theme.error)
            }
            .buttonStyle(.plain)
            .help("Удалить правило")
        }
        .padding(.horizontal, HDSpacing.md.rawValue)
        .padding(.vertical, HDSpacing.sm.rawValue)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            Text("Новое правило пост-обработки")
                .font(HDFont.featureHeading)
                .foregroundStyle(theme.ink)

            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Описание")
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                TextField("например: Замена слов-паразитов", text: $draftDescription)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Regex паттерн")
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                TextField("например: \\b(э-э-э|ну|типа)\\b", text: $draftPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(HDFont.monoLabel(size: 12))
                Text("Без регистра. Используй \\b для границ слов.")
                    .font(HDFont.micro)
                    .foregroundStyle(theme.muted)
            }

            VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
                Text("Замена (оставь пустым для удаления)")
                    .font(HDFont.formLabel)
                    .foregroundStyle(theme.ink)
                TextField("например: $1", text: $draftReplacement)
                    .textFieldStyle(.roundedBorder)
                    .font(HDFont.monoLabel(size: 12))
            }

            HStack {
                Spacer()
                HDButtonSecondary(title: "Отмена") {
                    showAddSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                HDButtonPrimary(title: "Добавить") {
                    commitDraft()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(draftPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(HDSpacing.xl.rawValue)
        .frame(width: 480)
        .background(theme.canvas)
    }

    private func commitDraft() {
        let pattern = draftPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        let rule = PostProcessingRule(
            pattern: pattern,
            replacement: draftReplacement.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addRule(rule)
        showAddSheet = false
    }
}
