//
//  FlowScreen.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI

struct FlowScreen: View {
    @ObservedObject var engine: FlowEngine
    @State private var showSections = false

    var body: some View {
        VStack(spacing: 12) {
            headerRow

            if engine.mode == .flatTire {
                arPlaceholder
            }

            stepCard

            if !engine.currentStep.choices.isEmpty {
                choiceButtons
            } else {
                navButtons
            }
        }
        .sheet(isPresented: $showSections) {
            sectionsSheet
        }
        .toolbar {
            if engine.mode == .deadBattery {
                ToolbarItem(placement: .automatic) {
                    Button("Sections") { showSections = true }
                }
            }
        }

    }

    private var headerRow: some View {
        HStack {
            Text(engine.progressText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(engine.mode.rawValue)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var arPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .frame(height: 170)
            .overlay(
                VStack(spacing: 6) {
                    Text("AR Area (Day 2)")
                        .font(.headline)
                    Text("Camera-aligned overlays will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            )
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(engine.currentStep.title)
                .font(.title2.weight(.bold))

            if !engine.currentStep.safety.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(engine.currentStep.safety) { flag in
                            SafetyChip(text: flag.rawValue)
                        }
                    }
                }
            }

            Divider()

            ScrollView {
                Text(engine.currentStep.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }

    private var navButtons: some View {
        HStack(spacing: 10) {
            Button("Back") { engine.goBack() }
                .buttonStyle(.bordered)
                .disabled(!engine.canGoBack)

            Spacer()

            Button(engine.canGoNext ? "Next" : "Done") {
                engine.goNext()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!engine.canGoNext)
        }
    }

    private var choiceButtons: some View {
        VStack(spacing: 10) {
            ForEach(engine.currentStep.choices) { choice in
                Button(choice.title) {
                    engine.select(choice)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            Button("Back") { engine.goBack() }
                .buttonStyle(.bordered)
                .disabled(!engine.canGoBack)
        }
    }

    private var sectionsSheet: some View {
        NavigationStack {
            List {
                ForEach(engine.stepsInOrder) { step in
                    Button {
                        engine.jump(to: step.id)
                        showSections = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.body.weight(.semibold))
                            Text(step.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Dead Battery Sections")
        }
    }
}

struct SafetyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.gray.opacity(0.18)))
    }
}
