//
//  StepProgressIndicator.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/18/26.
//

import SwiftUI

struct StepProgressIndicator: View {
    let steps: [RescueStep]
    let currentStepID: String
    let mode: RescueMode   // unused for now (ok to keep)

    private var currentIndex: Int {
        steps.firstIndex(where: { $0.id == currentStepID }) ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(steps.indices, id: \.self) { idx in
                Circle()
                    .fill(dotColor(for: idx))
                    .frame(
                        width: idx == currentIndex ? 10 : 8,
                        height: idx == currentIndex ? 10 : 8
                    )
                    .scaleEffect(idx == currentIndex ? 1.06 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: currentStepID)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func dotColor(for idx: Int) -> Color {
        idx <= currentIndex ? Color.accentColor : Color.gray.opacity(0.25)
    }
}

