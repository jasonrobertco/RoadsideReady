//
//  FlowScreen.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI
import UIKit

private extension View {
    func rrShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
}

struct FlowScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            contentArea
        }
        .safeAreaInset(edge: .bottom) {
            bottomDock
                .background(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showSections) {
            sectionsSheet
        }
        .sheet(isPresented: $showCompletion) {
            CompletionSheet(
                onViewArticles: { onOpenArticles() },
                onRestart: {
                    while engine.canGoBack { engine.goBack() }
                }
            )
        }
        .sheet(isPresented: $showLugSetup) {
            LugSetupSheet(selected: $pendingLugCount) { n in
                lugCount = n
                arSession.confirmLugSetup(n)
                arSession.lock()
            }
        }
        .onAppear {
            // Restore any saved choice for the initial step
            if let saved = choiceMemory[engine.currentStep.id] {
                selectedChoiceID = saved
            } else {
                selectedChoiceID = nil
            }
            // Speak the initial step if audio instructions are enabled
            if voiceAssistEnabled {
                speech.speak(speechText)
            }
        }
        .onChange(of: engine.currentStep.id) {
            // Restore previously selected choice for this step, if any
            if let saved = choiceMemory[engine.currentStep.id] {
                selectedChoiceID = saved
            } else {
                selectedChoiceID = nil
            }
            // Speak updated instructions if enabled
            if voiceAssistEnabled {
                speech.speak(speechText)
            }
            // Show completion when reaching the last step
            if engine.currentStep.id == engine.stepsInOrder.last?.id {
                showCompletion = true
            }
        }
    }
    
    @Environment(\.horizontalSizeClass) private var hSize

    @ObservedObject var engine: FlowEngine
    let onOpenArticles: () -> Void
    @State private var showSections = false
    @State private var safetyChecks: [Bool] = Array(repeating: false, count: 4)
    @State private var selectedChoiceID: String? = nil
    @State private var choiceMemory: [String: String] = [:]

    @State private var cameraEverOpened = false
    @State private var showARLugSetup = false
    @StateObject private var arSession = ARSessionModel()
    @AppStorage("lugCount") private var lugCount: Int = 5
    @AppStorage("voiceAssistEnabled") private var voiceAssistEnabled: Bool = false
    @AppStorage("voiceControlEnabled") private var voiceControlEnabled: Bool = false
    @StateObject private var speech = SpeechController()
    private let voiceControlInstructionsText =
    "Voice help. With Voice Control, you can say: Tap Next, or Tap Back. With VoiceOver, swipe to navigate and double-tap to activate."
    
    @State private var showCompletion = false
    @State private var showLugSetup = false
    @State private var pendingLugCount: Int = 5

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

    private func heroSymbol(for stepID: String) -> String {
        switch stepID {
        case "ft_loosen":    return "wrench.and.screwdriver"
        case "ft_jackpoint": return "location.north.circle"
        case "ft_jackup":    return "arrow.up.to.line.circle"
        case "ft_remove":    return "arrow.right.circle"
        case "ft_mount":     return "arrow.left.circle"
        case "ft_lower":     return "arrow.down.to.line.circle"
        default:               return "info.circle"
        }
    }

    private func heroTags(for stepID: String) -> [String] {
        switch stepID {
        case "ft_jackpoint", "ft_jackup":
            return ["Pinch points", "Heavy load"]
        default:
            return []
        }
    }

    private var toolsItems: [String] {
        // Convert the step body into a clean list:
        // - Removes "Find:" line
        // - Extracts "- item" bullets
        engine.currentStep.body
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.lowercased() != "find:" }
            .compactMap { line in
                if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                return nil
            }
    }

    private var toolsRightPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Centered infographic inside the right panel
            HStack {
                Spacer()
                Image(heroAssetName) // uses your existing mapping (hero_tire, etc.)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)   // controls size in right panel
                    .accessibilityHidden(true)
                Spacer()
            }
            .padding(.top, 6)
            .padding(.bottom, 6)

            Text("Tools needed")
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(toolsItems, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(item)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.vertical, 6)

            Spacer(minLength: 0)
        }
    }

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

    private var safetyReady: Bool {
        engine.currentStep.id != "ft_safety" || safetyChecks.allSatisfy { $0 }
    }

    private var alignmentReady: Bool {
        engine.currentStep.id != "ft_align" || arSession.isAligned
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

    private var panelDividerVertical: some View {
        Capsule()
            .fill(Color.black.opacity(0.08))
            .frame(width: 6)
            .padding(.vertical, 28)
    }

    private var panelDividerHorizontal: some View {
        Capsule()
            .fill(Color.black.opacity(0.08))
            .frame(height: 6)
            .padding(.horizontal, 28)
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
            .rrShadow()
    }

    private var audioInstructionsPill: some View {
        Button {
            speech.stop()
            voiceAssistEnabled.toggle()
            speech.speak(voiceAssistEnabled ? "Audio instructions on" : "Audio instructions off")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceAssistEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text("Audio Instructions")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(voiceAssistEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(voiceAssistEnabled ? Color(white: 0.15) : Color.gray.opacity(0.30), in: Capsule())
        }
        .rrShadow()
        .buttonStyle(.plain)
    }
    
    private var voiceControlPill: some View {
        Button {
            speech.stop()
            voiceControlEnabled.toggle()
            if voiceControlEnabled {
                speech.speak(voiceControlInstructionsText)
            } else {
                speech.speak("Voice control off")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceControlEnabled ? "mic.fill" : "mic.slash.fill")
                Text("Voice Control")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(voiceControlEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(voiceControlEnabled ? Color(white: 0.15) : Color.gray.opacity(0.30), in: Capsule())
        }
        .buttonStyle(.plain)
        .rrShadow()
        .accessibilityLabel("Voice control")
        .accessibilityHint("Plays voice control instructions and toggles state")
    }

    private var arTopText: String? {
        guard cameraEverOpened else { return nil }
        if let s = arSession.statusText { return s }
        if !arSession.hasAnchor { return "Tap floor or wall to place • Confirm position • Reset AR if needed" }
        if !arSession.lugSetupConfirmed { return "Confirm position • Reset AR if needed • Tap Continue to set lug count (5–8)" }
        if engine.currentStep.id == "ft_loosen" {
            return "Tap each lug marker after loosening ¼–½ turn (do not remove)"
        }
        return nil
    }

    private var arTopPhase: ARSessionModel.StatusPhase {
        arSession.statusPhase
    }

    private func arTopPill(text: String) -> some View {
        HStack(spacing: 8) {
            if arTopPhase == .resetting {
                ProgressView().tint(.white)
            } else if arTopPhase == .ready {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
            }

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .rrShadow()
    }

    // MARK: - AR-only lug setup UI (does NOT affect flow Continue/Next)
    private var shouldShowARLugContinue: Bool {
        cameraEverOpened &&
        arSession.hasAnchor &&
        !arSession.lugSetupConfirmed &&
        !showARLugSetup
    }

    private var arLugContinuePill: some View {
        Button { showARLugSetup = true } label: {
            Text("Continue")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var arLugSliderPill: some View {
        HStack(spacing: 12) {
            Text("Enter lug nuts (5–8)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(lugCount)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 22, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { Double(lugCount) },
                    set: { lugCount = Int($0.rounded()) }
                ),
                in: 5...8,
                step: 1,
                onEditingChanged: { editing in
                    if !editing {
                        arSession.confirmLugSetup(lugCount)   // auto-confirm on release
                        showARLugSetup = false
                    }
                }
            )
            .frame(width: 170)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
        .rrShadow()
    }

    private var showARLugEntry: Bool {
        cameraEverOpened && arSession.hasAnchor && arSession.isLocked && !showARLugSetup
    }

    private var arLugEntryPill: some View {
        Button { showARLugSetup = true } label: {
            Text(arSession.lugSetupConfirmed ? "Lugs: \(lugCount)  •  Edit" : "Continue")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private var startARCard: some View {
        Button {
            cameraEverOpened = true
        } label: {
            VStack(spacing: 14) {
                ZStack {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 70, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))

                    Image(systemName: "camera.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }

                Text("Start AR Camera")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Tap to open the camera and place the guide.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var visualPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.92))

            Group {
                if cameraEverOpened {
                    #if targetEnvironment(simulator)
                    ARUnavailableInlineView()
                    #else
                    ARViewContainer(
                        currentStepID: engine.currentStep.id,
                        lugCount: lugCount,
                        sessionModel: arSession,
                        isActive: true
                    )
                    #endif
                } else {
                    startARCard
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(alignment: .topLeading) {
            if cameraEverOpened {
                Button { arSession.requestReset() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset AR")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    .rrShadow()
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .overlay(alignment: .top) {
            if let t = arTopText {
                arTopPill(text: t)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if cameraEverOpened {
                ZStack(alignment: .bottom) {
                    if showARLugSetup {
                        arLugSliderPill
                            .padding(.bottom, 12)
                    } else if showARLugEntry {
                        arLugEntryPill
                            .padding(.bottom, 12)
                    }
                }
                .padding(12)
            }
        }
        .rrShadow()
    }

    private var stepCard: some View {
        stepCardContent
            .padding()
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.04), lineWidth: 1))
            .rrShadow()
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

    private struct InstructionHero: View {
        let symbol: String
        let title: String

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    private struct TagChip: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(s)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Unified header across all steps
            HStack(spacing: 8) {
                Spacer()
                voiceControlPill
                audioInstructionsPill
                stepPill
            }

            InstructionHero(
                symbol: heroSymbol(for: engine.currentStep.id),
                title: engine.currentStep.title
            )

            let tags = heroTags(for: engine.currentStep.id)
            if !tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { TagChip(text: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
            }

            // centered infographic image (moved from left panel)
            if UIImage(named: heroAssetName) != nil {
                Image(heroAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .padding(.top, 2)
            }

            if engine.currentStep.id != "ft_safety", !engine.currentStep.safety.isEmpty {
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
                        .padding(.bottom, 8)

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
                if engine.currentStep.id == "ft_tools" {
                    toolsRightPanelContent
                } else {
                    if engine.currentStep.id == "ft_tools" {
                        toolsRightPanelContent
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

    private var contentArea: some View {
        GeometryReader { geo in
            Group {
                if hSize == .regular {
                    // iPad / landscape (and iPad portrait): 50/50 side-by-side
                    let spacing: CGFloat = 12
                    let leftW = (geo.size.width - spacing) / 2

                    HStack(alignment: .top, spacing: spacing) {
                        visualPanel
                            .frame(width: leftW)
                            .frame(maxHeight: .infinity)

                        panelDividerVertical

                        stepCard
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                } else {
                    // iPhone / compact: orientation-aware split
                    let spacing: CGFloat = 12
                    let isLandscape = geo.size.width > geo.size.height
                    let ratio: CGFloat = isLandscape ? 0.55 : 0.35   // tweak portrait 0.30–0.38 if needed

                    let available = geo.size.height - spacing
                    let topH = max(180, min(available * ratio, 360))

                    VStack(spacing: spacing) {
                        visualPanel
                            .frame(height: topH)
                            .frame(maxWidth: 420)
                            .frame(maxWidth: .infinity, alignment: .center)

                        panelDividerHorizontal

                        stepCard
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            .transaction { $0.animation = nil }
        }
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
                .background(alignment: .center) {
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .offset(y: 2)
                }
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                        .offset(y: 2)
                )
                .rrShadow()
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
            Button {
                handleNext()
            } label: {
                Text(firstContinueEnabled ? "Continue" : "Complete checklist to continue")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityHint("Start the guided steps")
            .buttonStyle(RRPrimaryPillButtonStyle())
            .frame(width: 320, height: 48)
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
        // If this step has choices, Next takes the selected one, or defaults to the first.
        if !engine.currentStep.choices.isEmpty {
            let choice = selectedChoice ?? engine.currentStep.choices.first!
            engine.select(choice)
            return
        }

        engine.goNext()
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
            .rrShadow()
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

// In FlowScreen.swift

private struct ChecklistRow: View {
    let title: String
    let subtitle: String
    @Binding var isChecked: Bool

    var body: some View {
        Button { isChecked.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))          // changed
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)                       // changed
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14) // slightly more breathing room
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


private struct SafetyAdvisoryCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red.opacity(0.85))
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
                    Text("Voice Assistant")
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
        .accessibilityLabel("Voice Assistant. Tap to hear instructions. Use VoiceOver to read steps aloud. With Voice Control, say Tap Next or Tap Back.")
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

private struct CompletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onViewArticles: () -> Void
    let onRestart: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Spacer(minLength: 6)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.green)

                Text("Steps complete")
                    .font(.title3.weight(.semibold))

                Text("You can review Articles for aftercare and safety notes, or restart the guide.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)

                VStack(spacing: 10) {
                    Button {
                        onViewArticles()
                        dismiss()
                    } label: {
                        Label("View Articles", systemImage: "newspaper")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onRestart()
                        dismiss()
                    } label: {
                        Text("Restart guide")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LugSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Int
    let onConfirm: (Int) -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter the amount of lug nuts")
                    .font(.title3.weight(.semibold))

                Text("Selected: \(selected)")
                    .font(.headline)

                Slider(
                    value: Binding(
                        get: { Double(selected) },
                        set: { selected = Int($0.rounded()) }
                    ),
                    in: 5...8,
                    step: 1
                )

                Button {
                    onConfirm(selected)
                    dismiss()
                } label: {
                    Text("Confirm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Lug setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


