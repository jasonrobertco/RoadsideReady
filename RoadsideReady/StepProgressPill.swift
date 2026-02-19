import SwiftUI

struct StepProgressPill: View {
    let steps: [RescueStep]
    let currentStepID: String

    private var currentIndex: Int {
        steps.firstIndex(where: { $0.id == currentStepID }) ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(steps.indices, id: \.self) { idx in
                Circle()
                    .fill(idx <= currentIndex ? Color.accentColor : Color.gray.opacity(0.28))
                    .frame(width: idx == currentIndex ? 9 : 7,
                           height: idx == currentIndex ? 9 : 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
