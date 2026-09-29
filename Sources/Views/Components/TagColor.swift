import SwiftUI

/// Twenty's select/multi-select option colours (`FieldMetadataOption.color`).
enum TagColor {
    static func color(for name: String?) -> Color {
        switch name?.lowercased() {
        case "green": Color(red: 0.16, green: 0.62, blue: 0.35)
        case "turquoise": Color(red: 0.07, green: 0.62, blue: 0.62)
        case "sky": Color(red: 0.05, green: 0.60, blue: 0.85)
        case "blue": Color(red: 0.23, green: 0.40, blue: 0.93)
        case "purple": Color(red: 0.55, green: 0.33, blue: 0.87)
        case "pink": Color(red: 0.87, green: 0.28, blue: 0.60)
        case "red": Color(red: 0.87, green: 0.24, blue: 0.24)
        case "orange": Color(red: 0.93, green: 0.49, blue: 0.13)
        case "yellow": Color(red: 0.80, green: 0.62, blue: 0.00)
        default: Color.gray
        }
    }
}

/// A coloured pill used for select and multi-select values.
struct TagChip: View {
    let label: String
    let colorName: String?

    var body: some View {
        let tint = TagColor.color(for: colorName)
        Text(label)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Lays out children left-to-right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += (isFirst ? 0 : spacing) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
