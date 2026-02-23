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

                    Spacer(minLength: 12)

                    issueMenu
                        .layoutPriority(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                FlowScreen(engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }

    private var issueTitle: String { engine.mode.rawValue }

    private var issueSymbol: String {
        switch engine.mode {
        case .flatTire: return "tirepressure"
        case .deadBattery: return "battery.0"
        }
    }

    private var issueMenu: some View {
        Menu {
            Button("Flat Tire") { engine.setMode(.flatTire) }
            Button("Dead Battery") { engine.setMode(.deadBattery) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: issueSymbol)
                Text(issueTitle)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .transaction { $0.animation = nil }
    }
}

