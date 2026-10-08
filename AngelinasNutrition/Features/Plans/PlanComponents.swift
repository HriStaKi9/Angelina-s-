import SwiftUI

extension PersonalPlan {
    var accentColor: Color {
        if ThemeVariant.current == .steel { return Theme.Palette.berry }
        return accent == "apricot" ? Theme.Palette.apricot : Theme.Palette.berry
    }
}

/// Toolbar menu that switches plan content between Bulgarian and English.
struct LanguageMenu: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        Menu {
            ForEach(ContentLanguage.allCases) { language in
                Button {
                    store.language = language
                } label: {
                    if store.language == language {
                        Label(language.title, systemImage: "checkmark")
                    } else {
                        Text(language.title)
                    }
                }
            }
        } label: {
            Text(store.language.shortTitle)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.Palette.surfaceMuted, in: Capsule())
        }
        .accessibilityLabel("Plan language")
    }
}

/// Circle with the plan owner's initial, tinted with their accent.
struct PlanAvatar: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan
    var size: CGFloat = 44

    var body: some View {
        Text(plan.name[store.language].prefix(1))
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(plan.accentColor.gradient, in: Circle())
    }
}

/// Large metric used in plan headers: "2200–2400" over "kcal / day".
struct PlanMetric: View {
    let value: String
    let caption: String
    var tint: Color = Theme.Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders an `InfoSection`: a bulleted card, or a tinted callout for warnings/info.
struct InfoSectionView: View {
    @Environment(ProfileStore.self) private var store
    let section: InfoSection

    var body: some View {
        switch section.style {
        case .list:
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: section.title[store.language])
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                            BulletText(text: item[store.language])
                        }
                    }
                }
            }
        case .warning, .info:
            Callout(title: section.title[store.language],
                    items: section.items.map { $0[store.language] },
                    isWarning: section.style == .warning)
        }
    }
}

struct Callout: View {
    let title: String
    let items: [String]
    let isWarning: Bool

    private var tint: Color { isWarning ? Theme.Palette.berry : Theme.Palette.lavender }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }
}

struct BulletText: View {
    let text: String
    var tint: Color = Theme.Palette.inkSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Circle().fill(tint).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "If you see → do" rows, each as a two-line card row.
struct AdjustmentTableView: View {
    @Environment(ProfileStore.self) private var store
    let table: AdjustmentTable
    var tint: Color = Theme.Palette.sage

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: table.title[store.language])
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.when[store.language])
                                .font(.subheadline)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Label {
                                Text(row.action[store.language])
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(tint)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Navigation row into a guide screen.
struct GuideLinkRow: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.Palette.sage

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .frame(width: 36, height: 36)
                .foregroundStyle(tint)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            Text(title).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }
}

/// Card for choosing a personal plan (onboarding, empty states).
struct PlanChoiceCard: View {
    @Environment(ProfileStore.self) private var store
    let plan: PersonalPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                PlanAvatar(plan: plan, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name[store.language]).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Text(plan.nutrition.stats[store.language])
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? plan.accentColor : Theme.Palette.hairline)
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(isSelected ? plan.accentColor : Theme.Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Generic screen listing guide sections (rules, breastfeeding notes, progression…).
struct PlanGuideView: View {
    @Environment(ProfileStore.self) private var store
    let title: Localized
    var intro: [Localized] = []
    let sections: [InfoSection]
    var adjustments: AdjustmentTable?
    var footnote: Localized?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !intro.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            ForEach(Array(intro.enumerated()), id: \.offset) { _, item in
                                BulletText(text: item[store.language])
                            }
                        }
                    }
                }
                ForEach(sections) { InfoSectionView(section: $0) }
                if let adjustments { AdjustmentTableView(table: adjustments) }
                if let footnote {
                    Callout(title: store.language == .bg ? "Важно" : "Important", items: [footnote[store.language]], isWarning: false)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(title[store.language])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
    }
}

extension Double {
    /// "42.5" / "40" – weights and measurements without trailing zeros.
    var trimmed: String { formatted(.number.precision(.fractionLength(0...1))) }
}

extension SetSuggestion {
    /// "4 × 6–8 · 45 кг", "3 × 8–10 · без тежест", "2 × 35 сек".
    func summary(_ store: ProfileStore, load: ExerciseTracking.Load, perSide: Bool) -> String {
        var amount: String
        if let seconds {
            amount = "\(sets) × \(seconds) \(store.t("сек", "s"))"
        } else if let reps {
            amount = "\(sets) × \(reps.lowerBound == reps.upperBound ? "\(reps.lowerBound)" : "\(reps.lowerBound)–\(reps.upperBound)")"
        } else {
            amount = "\(sets)"
        }
        if perSide { amount += store.t(" на страна", " per side") }
        if let weight {
            let perHand = load == .dumbbells ? store.t("2 × ", "2 × ") : ""
            return "\(amount) · \(perHand)\(weight.trimmed) \(store.t("кг", "kg"))"
        }
        if load.usesWeight { return "\(amount) · \(chooseWeight ? store.t("избери тежест", "pick a weight") : store.t("без тежест", "bodyweight"))" }
        return amount
    }
}

extension LoggedSet {
    /// "45 × 8", "35 s", "× 10".
    func summary(_ store: ProfileStore) -> String {
        if let seconds { return "\(seconds) \(store.t("сек", "s"))" }
        let reps = reps.map(String.init) ?? "–"
        if let weight { return "\(weight.trimmed) × \(reps)" }
        return "× \(reps)"
    }
}
