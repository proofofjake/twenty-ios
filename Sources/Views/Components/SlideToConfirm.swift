import SwiftUI

/// "Slide to delete": drag the knob all the way across to confirm, so a
/// stray tap can't do it. Springs back if let go early. VoiceOver users get
/// a plain button (its default action), since sliding isn't possible there.
struct SlideToConfirm: View {
    let title: String
    var systemImage = "trash"
    var tint: Color = .red
    var isWorking = false
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var confirmed = 0

    private let height: CGFloat = 56
    private let inset: CGFloat = 4
    /// How far across (0…1) counts as confirmed.
    private static let commit: CGFloat = 0.9

    var body: some View {
        GeometryReader { geometry in
            let knob = height - inset * 2
            let travel = max(geometry.size.width - knob - inset * 2, 1)
            let progress = min(max(offset / travel, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint.opacity(0.35))
                    .frame(width: knob + inset * 2 + offset)
                HStack(spacing: 6) {
                    Text(title).fontWeight(.semibold)
                    Image(systemName: "chevron.right.2")
                }
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.leading, knob)
                .opacity(isWorking ? 0 : 1 - Double(progress) * 1.4)
                ZStack {
                    Circle().fill(tint)
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: systemImage).font(.headline).foregroundStyle(.white)
                    }
                }
                .frame(width: knob, height: knob)
                .padding(.leading, inset)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !isWorking else { return }
                            offset = min(max(value.translation.width, 0), travel)
                        }
                        .onEnded { _ in
                            guard !isWorking else { return }
                            if offset / travel >= Self.commit {
                                offset = travel
                                confirmed += 1
                                action()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
                            }
                        }
                )
            }
        }
        .frame(height: height)
        .sensoryFeedback(.success, trigger: confirmed)
        .onChange(of: isWorking) { _, working in
            // A failed attempt (back to idle without leaving) resets the knob.
            if !working { withAnimation(.spring) { offset = 0 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !isWorking { action() } }
        .accessibilityIdentifier("slide.confirm")
    }
}
