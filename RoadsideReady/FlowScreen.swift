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
    @AppStorage("voiceAssistEnabled") private var voiceAssistEnabled: Bool = false
    @StateObject private var speech = SpeechController()
    @State private var speakVoiceControlAfterContinue = false
    private let voiceControlInstructionsText =
    "Voice help. With Voice Control, you can say: Tap Next, or Tap Back. With VoiceOver, swipe to navigate and double-tap to activate."

    @State private var splitFracRegular: CGFloat = 0.30   // left panel width fraction on iPad
    @State private var splitFracCompact: CGFloat = 0.28   // top panel height fraction on iPhone
    @GestureState private var dragDeltaRegular: CGFloat = 0
    @GestureState private var dragDeltaCompact: CGFloat = 0
    @State private var regularStopIndex: Int = 1   // 0=0.25, 1=0.50, 2=0.75
    @State private var compactStopIndex: Int = 1

    private func clamp(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(x, a), b) }

    private func snap(_ x: CGFloat, presets: [CGFloat]) -> CGFloat {
        presets.min(by: { abs($0 - x) < abs($1 - x) }) ?? x
    }

    private let regularPresets: [CGFloat] = [0.25, 0.50, 0.75]
    private let compactPresets: [CGFloat] = [0.25, 0.50, 0.75]

    private let snapStops: [CGFloat] = [0.25, 0.50, 0.75]

    private func nearestStopIndex(_ x: CGFloat) -> Int {
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (i, s) in snapStops.enumerated() {
            let d = abs(s - x)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    @State private var showARFullScreen = false

    private var arAvailable: Bool {
    #if targetEnvironment(simulator)
        return false
    #else
        return true
    #endif
    }

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

    private var speechText: String {
        // Make bullets read naturally
        let cleanedBody = engine.currentStep.body
            .replacingOccurrences(of: "\n- ", with: ". ")
            .replacingOccurrences(of: "\n", with: ". ")

        if engine.currentStep.id == "ft_safety" {
            return """
            Safety check. Tap each item to confirm.
            Hazard lights on. Pulled over safely. Parking brake set. Passengers safe.
            """
        }

        return "\(engine.currentStep.title). \(cleanedBody)"
    }

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
        GeometryReader { geo in
            VStack(spacing: 0) {
                contentArea
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                bottomDock
                    .padding(.bottom, max(12, geo.safeAreaInsets.bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(edges: .bottom)
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
            speech.stop()

            if speakVoiceControlAfterContinue {
                speakVoiceControlAfterContinue = false
                speech.speak(voiceControlInstructionsText)
                return
            }

            if voiceAssistEnabled {
                speech.speak(speechText)
            }
        }
        .onAppear {
            // Always start muted
            voiceAssistEnabled = false
            // Ensure no speech is playing when the screen appears
            speech.stop()
        }
    }

    private var contentArea: some View {
        GeometryReader { geo in
            Group {
                if hSize == .regular {
                    let handleW: CGFloat = 28
                    let spacing: CGFloat = 12
                    let contentW = geo.size.width - handleW - (spacing * 2)
                    let base = snapStops[regularStopIndex]
                    let proposed = clamp(base + (dragDeltaRegular / max(contentW, 1)), 0.25, 0.75)
                    let liveIndex = nearestStopIndex(proposed)
                    let frac = snapStops[liveIndex]
                    let leftW = contentW * frac

                    HStack(alignment: .top, spacing: spacing) {
                        visualPanel
                            .frame(width: leftW)
                            .frame(maxHeight: .infinity)

                        splitHandleHorizontal(totalContentWidth: contentW)

                        stepCard
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .transaction { $0.animation = nil }
                } else {
                    let handleH: CGFloat = 22
                    let spacing: CGFloat = 12
                    let contentH = geo.size.height - handleH - spacing
                    let base = snapStops[compactStopIndex]
                    let proposed = clamp(base + (dragDeltaCompact / max(contentH, 1)), 0.25, 0.75)
                    let liveIndex = nearestStopIndex(proposed)
                    let frac = snapStops[liveIndex]
                    let topH = contentH * frac

                    VStack(spacing: spacing) {
                        visualPanel
                            .frame(height: topH)
                            .frame(maxWidth: 420)
                            .frame(maxWidth: .infinity, alignment: .center)

                        splitHandleVertical(totalContentHeight: contentH)

                        stepCard
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .transaction { $0.animation = nil }
                }
            }
        }
    }
    
    private func splitHandleHorizontal(totalContentWidth: CGFloat) -> some View {
        return Color.clear
            .frame(width: 28)
            .contentShape(Rectangle())
            .overlay(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(width: 12, height: 72)
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

                    // slit
                    Capsule()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 3, height: 26)
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragDeltaRegular) { value, state, _ in
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let base = snapStops[regularStopIndex]
                        let proposed = clamp(base + value.translation.width / max(totalContentWidth, 1), 0.25, 0.75)
                        let idx = nearestStopIndex(proposed)
                        withAnimation(.snappy) { regularStopIndex = idx }
                    }
            )
    }

    private func splitHandleVertical(totalContentHeight: CGFloat) -> some View {
        return Color.clear
            .frame(height: 22)
            .contentShape(Rectangle())
            .overlay(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(width: 72, height: 12)
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))

                    // slit
                    Capsule()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 26, height: 3)
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragDeltaCompact) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let base = snapStops[compactStopIndex]
                        let proposed = clamp(base + value.translation.height / max(totalContentHeight, 1), 0.25, 0.75)
                        let idx = nearestStopIndex(proposed)
                        withAnimation(.snappy) { compactStopIndex = idx }
                    }
            )
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
    
    private var stepPill: some View {
        Text(engine.progressText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }

    private var audioInstructionsPill: some View {
        Button {
            // Always override any current speech first
            speech.stop()
            // Toggle mute state
            voiceAssistEnabled.toggle()
            // Announce the new status
            let phrase = voiceAssistEnabled ? "Audio instructions on" : "Audio instructions off"
            speech.speak(phrase)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceAssistEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text("Audio Instructions")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio instructions")
        .accessibilityHint("Toggles automatic voice instructions and announces status")
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            if engine.canGoBack {
                bottomNavRow
            } else {
                bottomContinueRow
            }

            HStack {
                Spacer(minLength: 0)
                StepProgressIndicator(
                    steps: engine.stepsInOrder,
                    currentStepID: engine.currentStep.id,
                    mode: engine.mode
                )
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.04), lineWidth: 1))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
    
    private var bottomContinueRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Continue") { handleNext() }
                .accessibilityHint("Start the guided steps")
                .buttonStyle(RRPrimaryPillButtonStyle())
                .frame(width: 220, height: 48)
                .disabled(!firstContinueEnabled)
            Spacer(minLength: 0)
        }
    }
    
    private var bottomNavRow: some View {
        HStack(spacing: 12) {
            Button("Back") { engine.goBack() }
                .accessibilityHint("Go to the previous step")
                .buttonStyle(RRSecondaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!engine.canGoBack)

            Button("Next") { handleNext() }
                .accessibilityHint("Go to the next step")
                .buttonStyle(RRPrimaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!canTapNext)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func handleNext() {
        if isFirstScreen && engine.currentStep.id == "ft_safety" {
            speakVoiceControlAfterContinue = true
        }
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
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )

            ZStack {
                // Infographic layer (always available)
                Group {
                    if UIImage(named: heroAssetName) != nil {
                        Image(heroAssetName).resizable()
                    } else if UIImage(named: "hero_tire") != nil {
                        Image("hero_tire").resizable()
                    } else {
                        Image(systemName: engine.mode == .flatTire ? "tirepressure" : "battery.0")
                            .resizable()
                            .foregroundStyle(.secondary)
                            .padding(40)
                    }
                }
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .opacity(visualMode == .infographic ? 1 : 0)

                if cameraEverOpened || visualMode == .camera {
                    Group {
    #if targetEnvironment(simulator)
                        ARUnavailableInlineView()
    #else
                        ARViewContainer(currentStepID: engine.currentStep.id, isAligned: $isAligned)
    #endif
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(visualMode == .camera ? 1 : 0)
                    .allowsHitTesting(visualMode == .camera)
                }
            }
            .overlay(alignment: .topTrailing) {
                if visualMode == .camera && arAvailable {
                    Button { showARFullScreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel("Open camera fullscreen")
                }
            }
            .fullScreenCover(isPresented: $showARFullScreen) {
                ARFullScreenView(currentStepID: engine.currentStep.id, isAligned: $isAligned)
            }
        }
        .overlay(alignment: .bottom) {
            visualModeToggle.padding(12)
        }
    }

    private var visualModeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(.infographic, system: "doc.text.image", label: "Infographic")
            Divider().opacity(0.25).frame(height: 18)
            toggleButton(.camera, system: "camera.viewfinder", label: "Camera")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.04), lineWidth: 1))
    }

    private func toggleButton(_ mode: VisualMode, system: String, label: String) -> some View {
        Button { setVisualMode(mode) } label: {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 32)
                .foregroundStyle(mode == visualMode ? Color.accentColor : Color.secondary)
                .background(mode == visualMode ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var stepCard: some View {
        ZStack(alignment: .topTrailing) {
            stepCardContent

            HStack(spacing: 8) {
                audioInstructionsPill
                stepPill
            }
            .padding(12)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.04), lineWidth: 1))
    }

    private var listenPrimaryButton: some View {
        Button { speech.toggle(speechText) } label: {
            HStack(spacing: 10) {
                Image(systemName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                Text(speech.isSpeaking ? "Stop audio" : "Listen to instructions")
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isSpeaking ? "Stop audio" : "Play audio")
    }

    private var stepCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Unified header across all steps
            Text(engine.currentStep.title)
                .font(.title3.weight(.semibold))

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

            // Body content: safety checklist or regular body
            if engine.currentStep.id == "ft_safety" {
                VStack(alignment: .leading, spacing: 12) {
                    SafetyAdvisoryCard(text: "If you’re in danger, call local emergency services.")
                    VoiceAssistCard(action: { speech.toggle(speechText) })

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
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )
                }
                Spacer(minLength: 0)
            } else {
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
                    .fill(Color(uiColor: .tertiarySystemBackground))
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
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct VoiceAssistCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice + AR help")
                        .font(.subheadline.weight(.semibold))

                    Text("Voice instructions and AR positioning are available for this issue. Use VoiceOver to read steps aloud. With Voice Control, say “Tap Next” or “Tap Back”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice and AR help. Tap to hear instructions. Use VoiceOver to read steps aloud. With Voice Control, say Tap Next or Tap Back.")
        .accessibilityHint("Plays the current step instructions.")
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

