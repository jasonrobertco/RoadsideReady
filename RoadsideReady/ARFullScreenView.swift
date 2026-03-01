import SwiftUI

struct ARFullScreenView: View {
    let currentStepID: String
    let lugCount: Int
    @ObservedObject var sessionModel: ARSessionModel
    @Environment(\.dismiss) private var dismiss

    private var arFullHintText: String? {
        if !sessionModel.hasAnchor {
            return "Tap a flat surface (floor or wall) near the tire to place the guide"
        }
        if currentStepID == "ft_loosen" {
            return "Tap each lug marker after loosening ¼–½ turn (do not remove)"
        }
        return nil
    }

    private func arCenterHint(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .padding(20)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ARViewContainer(currentStepID: currentStepID, lugCount: lugCount, sessionModel: sessionModel, isActive: true)
                    .ignoresSafeArea()

                if let t = arFullHintText {
                    arCenterHint(t)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }
}

