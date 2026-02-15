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

                Text("Roadside Ready")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Mode", selection: Binding(
                    get: { engine.mode },
                    set: { engine.setMode($0) }
                )) {
                    ForEach(RescueMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                FlowScreen(engine: engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }

}
