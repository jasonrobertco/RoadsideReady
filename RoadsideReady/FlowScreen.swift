//
//  FlowScreen.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI
import UIKit


struct FlowScreen: View {
    enum VisualMode { case infographic, camera }
    @Environment(\.horizontalSizeClass) private var hSize

    @ObservedObject var engine: FlowEngine
    @State private var showSections = false
    @State private var isAligned = false
    @State private var safetyChecks: [Bool] = Array(repeating: false, count: 4)
    @State private var selectedChoiceID: String? = nil
    @State private var choiceMemory: [String: String] = [:]
    @State private var visualMode: VisualMode = .infographic

    @State private var cameraEverOpened = false

    private let flatTireHeroMap: [String: String] = [
        "ft_safety": "hero_safety",
        "ft_tools": "hero_tire",
        "ft_spare_check": "hero_tire",
        "ft_chock": "hero_chock",
        "ft_loosen": "hero_lugs",
        "ft_jackpoint": "hero_jack",
        "ft_jackup": "hero_jack",
        "ft_remove": "hero_lugs",
        "ft_mount": "hero_tire",
        "ft_lower": "hero_jack",
        "ft_aftercare": "hero_tire",
    ]

    private var heroAssetName: String {
        if engine.mode == .flatTire {
            return flatTireHeroMap[engine.currentStep.id] ?? "hero_tire"
        } else {
            return "hero_battery"
        }
    }

    private var visualPanelHeight: CGFloat { hSize == .regular ? 280 : 220 }
    private var visualPanelWidth: CGFloat? { hSize == .regular ? 360 : nil }

    private func setVisualMode(_ mode: VisualMode) {
        if mode == .camera { cameraEverOpened = true }
        visualMode = mode
    }

    private var safetyReady: Bool {
        engine.currentStep.id != "ft_safety" || safetyChecks.allSatisfy { $0 }
    }

    private var alignmentReady: Bool {
        engine.currentStep.id != "ft_align" || isAligned
    }
    
    private var selectedChoice: RescueChoice? {
        guard let id = selectedChoiceID else { return nil }
        return engine.currentStep.choices.first { $0.id == id }
    }

    private var canAdvanceFromStep: Bool {
        engine.currentStep.choices.isEmpty ? engine.canGoNext : (selectedChoice != nil)
    }

    private var canTapNext: Bool {
        // Not gated by checklist/alignment.
        // Only disable on true end-of-flow.
        if !engine.currentStep.choices.isEmpty { return true }
        return engine.canGoNext
    }

    private var isFirstScreen: Bool { !engine.canGoBack }

    private var firstContinueEnabled: Bool {
        // Only gate the very first screen, and only if it’s the safety checklist step.
        if isFirstScreen && engine.currentStep.id == "ft_safety" {
            return safetyChecks.allSatisfy { $0 }
        }
        // Otherwise, let Continue work.
        return engine.canGoNext || !engine.currentStep.choices.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            if engine.currentStep.id != "ft_safety" { headerRow }
            contentArea
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .safeAreaInset(edge: .bottom) {
            bottomDock
        }
        .sheet(isPresented: $showSections) { sectionsSheet }
        .toolbar {
            if engine.mode == .deadBattery {
                ToolbarItem(placement: .automatic) {
                    Button("Sections") { showSections = true }
                }
            }
        }
        .onChange(of: engine.currentStep.id) { _, newID in
            if newID == "ft_safety" { safetyChecks = Array(repeating: false, count: 4) }
            // Keep AR alignment state across steps; do not reset isAligned here
            selectedChoiceID = choiceMemory[newID]
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if hSize == .regular {
            // iPad / landscape: side-by-side, both stretch full height
            HStack(alignment: .top, spacing: 12) {
                visualPanel
                    .frame(width: 360)
                    .frame(maxHeight: .infinity, alignment: .top)

                stepCard
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            // iPhone / portrait: centered visual panel (not full-width)
            VStack(spacing: 12) {
                visualPanel
                    .frame(maxWidth: 420)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity, alignment: .center)

                stepCard
            }
            .frame(maxWidth: .infinity, alignment: .top)
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

    private var sectionsSheet: some View {
        NavigationStack {
            List {
                ForEach(engine.stepsInOrder, id: \.id) { (step: RescueStep) in
                    HStack {
                        Text(step.title)
                        Spacer()
                        if step.id == engine.currentStep.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Sections")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSections = false }
                }
            }
        }
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            if engine.canGoBack {
                bottomNavRow
            } else {
                bottomContinueRow
            }

            StepProgressIndicator(
                steps: engine.stepsInOrder,
                currentStepID: engine.currentStep.id,
                mode: engine.mode
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }
    
    private var bottomContinueRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Continue") { handleNext() }
                .buttonStyle(RRPrimaryPillButtonStyle())
                .frame(width: 220, height: 48)
                .disabled(!firstContinueEnabled)
            Spacer(minLength: 0)
        }
    }
    
    private var bottomNavRow: some View {
        HStack(spacing: 12) {
            Button("Back") { engine.goBack() }
                .buttonStyle(RRSecondaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!engine.canGoBack)

            Button("Next") { handleNext() }
                .buttonStyle(RRPrimaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!canTapNext)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func handleNext() {
        // If this step has choices, Next takes the selected one, or defaults to the first.
        if !engine.currentStep.choices.isEmpty {
            let choice = selectedChoice ?? engine.currentStep.choices.first!
            engine.select(choice)
            return
        }

        engine.goNext()
    }


    private var visualPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )

            ZStack {
                // Infographic layer (always available)
                Group {
                    if UIImage(named: heroAssetName) != nil {
                        Image(heroAssetName)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    } else if UIImage(named: "hero_tire") != nil {
                        Image("hero_tire")
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    } else {
                        Image(systemName: engine.mode == .flatTire ? "tirepressure" : "battery.0")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(visualMode == .infographic ? 1 : 0)

                if cameraEverOpened || visualMode == .camera {
                    Group {
#if targetEnvironment(simulator)
                        ARUnavailableInlineView()
#else
                        ARViewContainer(currentStepID: engine.currentStep.id, isAligned: $isAligned)
#endif
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .opacity(visualMode == .camera ? 1 : 0)
                    .allowsHitTesting(visualMode == .camera)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button { setVisualMode(.infographic) } label: {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)

                Button { setVisualMode(.camera) } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            if engine.currentStep.id != "ft_safety" {
                // Title
                Text(engine.currentStep.title)
                    .font(.title2.weight(.bold))
            }

            // Safety step: simplified checklist layout (visuals are now in the persistent visualPanel)
            if engine.currentStep.id == "ft_safety" {
                VStack(alignment: .leading, spacing: 12) {
                    SafetyAdvisoryCard(text: "If you’re in danger, call local emergency services.")

                    Text("Safety check")
                        .font(.title3.weight(.semibold))

                    Text("Tap each item to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ChecklistRow(title: "Hazard lights on", subtitle: "Stay visible", isChecked: $safetyChecks[0])
                        Divider().opacity(0.5)
                        ChecklistRow(title: "Pulled over safely", subtitle: "Flat, well-lit spot", isChecked: $safetyChecks[1])
                        Divider().opacity(0.5)
                        ChecklistRow(title: "Parking brake set", subtitle: "Park / 1st gear", isChecked: $safetyChecks[2])
                        Divider().opacity(0.5)
                        ChecklistRow(title: "Passengers safe", subtitle: "Away from traffic", isChecked: $safetyChecks[3])
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
            } else {

                // Safety chips (other steps)
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

                // Body text (other steps)
                ScrollView {
                    Text(engine.currentStep.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if !engine.currentStep.choices.isEmpty {
                    Divider()
                    choiceSelector
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }
    
    private var choiceSelector: some View {
        let twoChoices = Array(engine.currentStep.choices.prefix(2))

        return HStack(spacing: 12) {
            ForEach(twoChoices, id: \.id) { (choice: RescueChoice) in
                let isSelected = (selectedChoiceID == choice.id)

                if isSelected {
                    Button {
                        selectedChoiceID = choice.id
                        choiceMemory[engine.currentStep.id] = choice.id
                    } label: {
                        Text(choice.title)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(RRPrimaryPillButtonStyle())
                } else {
                    Button {
                        selectedChoiceID = choice.id
                        choiceMemory[engine.currentStep.id] = choice.id
                    } label: {
                        Text(choice.title)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(RRSecondaryPillButtonStyle())
                }
            }
        }
    }


    private struct SafetyHeroIcon: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 120, height: 120)

                Image(systemName: "car.side.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.secondary)

                Circle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: 20, height: 20)
                    .offset(x: -22, y: 18)
            }
        }
    }


}

private struct RRPrimaryPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1.0 : 0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(isEnabled ? Color.accentColor : Color.gray.opacity(0.35))
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct RRSecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule().fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
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

private struct ChecklistRow: View {
    let title: String
    let subtitle: String
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(isChecked ? "checked" : "unchecked")")
    }
}

private struct SafetyAdvisoryCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safety advisory")
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ARUnavailableInlineView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.90)
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Camera unavailable in Simulator")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Using infographic instead.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
        }
    }
}

