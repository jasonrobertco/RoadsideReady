import SwiftUI

struct ARFullScreenView: View {
    let currentStepID: String
    @ObservedObject var sessionModel: ARSessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            #if targetEnvironment(simulator)
            ZStack {
                Color.black.ignoresSafeArea()
                Text("AR not available in Simulator")
                    .foregroundStyle(.white.opacity(0.85))
            }
            #else
            ARViewContainer(currentStepID: currentStepID, sessionModel: sessionModel)
                .ignoresSafeArea()
            #endif

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
