import SwiftUI

/// Rounded raised container used for nearly every block of content.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.sectionTitle).foregroundStyle(Theme.Palette.ink)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Selectable pill used for filters and onboarding choices.
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool
    var tint: Color = Theme.Palette.berry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.ink)
            .background(isSelected ? tint : Theme.Palette.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Small non-interactive label, e.g. "Beginner" or "Dumbbell".
struct Tag: View {
    let text: String
    var tint: Color = Theme.Palette.inkSecondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.berry

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Theme.Palette.onAccent)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Large selectable card used in onboarding (goal, location, level).
struct ChoiceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    var tint: Color = Theme.Palette.berry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(isSelected ? Theme.Palette.onAccent : tint)
                    .background(isSelected ? tint : tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.cardTitle).foregroundStyle(Theme.Palette.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.Palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? tint : Theme.Palette.hairline)
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(isSelected ? tint : Theme.Palette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// Exercise demo image loaded from the free-exercise-db CDN, with a soft placeholder.
struct ExerciseImage: View {
    let url: URL?
    var cornerRadius: CGFloat = Theme.Radius.medium

    var body: some View {
        // The clear base takes the proposed frame; the fill-scaled image is then clipped to it.
        Theme.Palette.surfaceMuted
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundStyle(Theme.Palette.inkSecondary.opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Wraps content onto multiple lines, used for chip groups.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var y: CGFloat; var height: CGFloat; var items: [(index: Int, x: CGFloat)] }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append((index, x))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
