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
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { idx in
                Circle()
                    .fill(dotColor(for: idx))
                    .frame(
                        width: idx == currentIndex ? 9 : 7,
                        height: idx == currentIndex ? 9 : 7
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func dotColor(for idx: Int) -> Color {
        idx <= currentIndex ? Color.accentColor : Color.gray.opacity(0.25)
    }
}

