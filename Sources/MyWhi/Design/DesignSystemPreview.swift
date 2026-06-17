// DesignSystemPreview.swift
// Visual catalog of every component in the design system.
// Open via WindowGroup with id "design-preview" — triggered from the
// menu bar About dialog or the debug menu item.
//
// This view exists only during alpha development. It's a living reference
// for verifying that the SwiftUI implementation matches the Cohere tokens
// in DESIGN-cohere (1).md.

import SwiftUI

struct DesignSystemPreviewView: View {
    @State private var recordState: HDRecordState = .idle
    @State private var filterSelected: Bool = false
    @State private var coralSelected: Bool = false
    @State private var sidebarSelection: SidebarDemo = .home

    enum SidebarDemo: Hashable { case home, scratchpad, insights, settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HDSpacing.xxl.rawValue) {

                header

                Section {
                    palette
                } header: {
                    sectionHeader("Palette")
                }

                Section {
                    typography
                } header: {
                    sectionHeader("Typography")
                }

                Section {
                    buttons
                } header: {
                    sectionHeader("Buttons")
                }

                Section {
                    recordStates
                } header: {
                    sectionHeader("Record Button")
                }

                Section {
                    cards
                } header: {
                    sectionHeader("Cards")
                }

                Section {
                    stats
                } header: {
                    sectionHeader("Stat Tiles")
                }

                Section {
                    sidebar
                } header: {
                    sectionHeader("Sidebar Items")
                }
            }
            .padding(HDSpacing.xl.rawValue)
        }
        .frame(minWidth: 760, minHeight: 700)
        .background(HDColor.canvas)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
            Text("MyWhi Design System")
                .font(HDFont.cardHeading)
                .hdTracking(-0.32)
            Text("Cohere tokens, SwiftUI implementation. v2.0-alpha.")
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: HDSpacing.xs.rawValue) {
            Text(title.uppercased())
                .font(HDFont.monoLabel(size: 12))
                .hdTracking(0.5)
                .foregroundStyle(HDColor.muted)
            Rectangle()
                .fill(HDColor.hairline)
                .frame(height: 1)
        }
    }

    // MARK: - Palette

    private var palette: some View {
        let swatches: [(String, Color)] = [
            ("primary",       HDColor.primary),
            ("cohereBlack",   HDColor.cohereBlack),
            ("ink",           HDColor.ink),
            ("deepGreen",     HDColor.deepGreen),
            ("coral",         HDColor.coral),
            ("coralSoft",     HDColor.coralSoft),
            ("canvas",        HDColor.canvas),
            ("softStone",     HDColor.softStone),
            ("paleGreen",     HDColor.paleGreen),
            ("paleBlue",      HDColor.paleBlue),
            ("muted",         HDColor.muted),
            ("slate",         HDColor.slate),
            ("bodyMuted",     HDColor.bodyMuted),
            ("hairline",      HDColor.hairline),
            ("borderLight",   HDColor.borderLight),
            ("cardBorder",    HDColor.cardBorder),
            ("actionBlue",    HDColor.actionBlue),
            ("focusBlue",     HDColor.focusBlue),
            ("formFocus",     HDColor.formFocus),
            ("error",         HDColor.error),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(swatches, id: \.0) { name, color in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: HDRadius.sm.rawValue)
                        .fill(color)
                        .overlay(
                            RoundedRectangle(cornerRadius: HDRadius.sm.rawValue)
                                .stroke(HDColor.borderLight, lineWidth: 1)
                        )
                        .frame(height: 56)
                    Text(name)
                        .font(HDFont.monoLabel(size: 11))
                        .foregroundStyle(HDColor.bodyMuted)
                }
            }
        }
    }

    // MARK: - Typography

    private var typography: some View {
        VStack(alignment: .leading, spacing: HDSpacing.md.rawValue) {
            Text("Hero Display 96").font(HDFont.heroDisplay).hdTracking(-1.92)
            Text("Product Display 72").font(HDFont.productDisplay).hdTracking(-1.44)
            Text("Section Heading 48").font(HDFont.sectionHeading).hdTracking(-0.48)
            Text("Card Heading 32").font(HDFont.cardHeading).hdTracking(-0.32)
            Text("Feature Heading 24").font(HDFont.featureHeading)
            Text("Body Large 18 — the quick brown fox jumps over the lazy dog")
                .font(HDFont.bodyLarge)
            Text("Body 16 — the quick brown fox jumps over the lazy dog")
                .font(HDFont.body)
            Text("BUTTON LABEL 14").font(HDFont.button)
            Text("Caption 14 — metadata and small explanatory text")
                .font(HDFont.caption)
            Text("MONO LABEL 14").font(HDFont.monoLabel)
            Text("Micro 12 — footer microcopy and small links").font(HDFont.micro)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            HStack(spacing: HDSpacing.md.rawValue) {
                HDButtonPrimary(title: "Submit") {}
                HDButtonPrimary(title: "Save", icon: "tray.and.arrow.down") {}
                HDButtonPrimary(title: "Disabled") {}
                    .disabled(true)
            }
            HStack(spacing: HDSpacing.lg.rawValue) {
                HDButtonSecondary(title: "Explore") {}
                HDButtonSecondary(title: "Learn more") {}
            }
            HStack(spacing: HDSpacing.sm.rawValue) {
                HDButtonPillOutline(title: "Filter", isSelected: filterSelected) {
                    filterSelected.toggle()
                }
                HDButtonPillOutline(title: "Topic", isSelected: false) {}
                HDButtonPillOutline(title: "Selected", isSelected: true) {}
            }
            HStack(spacing: HDSpacing.sm.rawValue) {
                HDButtonCoral(title: "Research", isSelected: coralSelected) {
                    coralSelected.toggle()
                }
                HDButtonCoral(title: "Engineering", isSelected: false) {}
            }
        }
    }

    // MARK: - Record button

    private var recordStates: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            HStack(spacing: HDSpacing.xl.rawValue) {
                stateColumn(.idle, "Idle")
                stateColumn(.recording, "Recording")
                stateColumn(.transcribing, "Transcribing")
            }
            HStack(spacing: HDSpacing.lg.rawValue) {
                Button("Set idle") { recordState = .idle }
                Button("Set recording") { recordState = .recording }
                Button("Set transcribing") { recordState = .transcribing }
            }
            .buttonStyle(.bordered)
        }
    }

    private func stateColumn(_ state: HDRecordState, _ label: String) -> some View {
        VStack(spacing: HDSpacing.sm.rawValue) {
            HDRecordButton(state: state) {}
            Text(label)
                .font(HDFont.caption)
                .foregroundStyle(HDColor.muted)
        }
    }

    // MARK: - Cards

    private var cards: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            HStack(spacing: HDSpacing.lg.rawValue) {
                HDCard(.canvas) {
                    VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                        Text("Canvas card")
                            .font(HDFont.featureHeading)
                        Text("White surface, 1px border-light.")
                            .font(HDFont.caption)
                            .foregroundStyle(HDColor.muted)
                    }
                }
                .frame(width: 240)

                HDCard(.stone) {
                    VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                        Text("Stone card")
                            .font(HDFont.featureHeading)
                        Text("Soft-stone warm neutral.")
                            .font(HDFont.caption)
                            .foregroundStyle(HDColor.muted)
                    }
                }
                .frame(width: 240)

                HDCard(.dark) {
                    VStack(alignment: .leading, spacing: HDSpacing.sm.rawValue) {
                        Text("Dark band")
                            .font(HDFont.featureHeading)
                            .foregroundStyle(HDColor.onDark)
                        Text("Deep-green surface.")
                            .font(HDFont.caption)
                            .foregroundStyle(HDColor.onDark.opacity(0.7))
                    }
                }
                .frame(width: 240)
            }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        VStack(alignment: .leading, spacing: HDSpacing.lg.rawValue) {
            HStack(spacing: HDSpacing.lg.rawValue) {
                HDStatTile(label: "Total words", value: "12 482", delta: "+12% this week", surface: .dark)
                HDStatTile(label: "Total chars", value: "78 910", surface: .dark)
                HDStatTile(label: "Streak", value: "7 days", delta: "longest 14", surface: .dark)
            }
            .padding(HDSpacing.lg.rawValue)
            .background(
                RoundedRectangle(cornerRadius: HDRadius.lg.rawValue)
                    .fill(HDColor.deepGreen)
            )

            HStack(spacing: HDSpacing.lg.rawValue) {
                HDStatTile(label: "Total words", value: "12 482")
                HDStatTile(label: "Total chars", value: "78 910")
                HDStatTile(label: "Streak", value: "7 days")
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HDSidebarItem(icon: "mic", label: "Запись",
                          section: SidebarDemo.home, selection: sidebarSelection)
            HDSidebarItem(icon: "doc.text", label: "Scratchpad",
                          section: SidebarDemo.scratchpad, badge: "12",
                          selection: sidebarSelection)
            HDSidebarItem(icon: "chart.bar", label: "Insights",
                          section: SidebarDemo.insights, selection: sidebarSelection)
            HDSidebarItem(icon: "gear", label: "Настройки",
                          section: SidebarDemo.settings, selection: sidebarSelection)
        }
        .padding(HDSpacing.md.rawValue)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HDRadius.md.rawValue)
                .fill(HDColor.softStone)
        )
    }
}