//
//  ARFullScreenView.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/18/26.
//

import SwiftUI

struct ARFullScreenView: View {
    let currentStepID: String
    @Binding var isAligned: Bool
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
            ARViewContainer(currentStepID: currentStepID, isAligned: $isAligned)
                .ignoresSafeArea()
            #endif

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }
}
