//
//  RootView.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI

struct RootView: View {
    @StateObject private var engine = FlowEngine()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                HStack {
                    Text("Roadside Ready")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button("Flat Tire") { engine.setMode(.flatTire) }
                        Button("Dead Battery") { engine.setMode(.deadBattery) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.circle")
                            Text(engine.mode.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }

                FlowScreen(engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }

}
