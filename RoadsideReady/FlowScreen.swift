//
//  FlowScreen.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI
import UIKit

// Panel text colors used throughout the glass card UI
private let rrPanelPrimary = Color.white.opacity(0.86)    // primary text on dark glass
private let rrPanelSecondary = Color.white.opacity(0.66)  // secondary/caption text on dark glass

private extension View {
    // Standard drop shadow used on floating cards and panels
    func rrShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
    
    // Lighter shadow used on pill-shaped badges (step counter, audio pill, etc.)
    func rrPillShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
    }
    
    // White text with a drop shadow so it reads clearly over dark glass backgrounds
    func rrStepTitleOnGlass() -> some View {
        self
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
    }
    
    // Shared frosted-glass card style: dark-tinted ultraThin material + subtle gradient border
    func rrGlassCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .allowsHitTesting(false)   // ✅ IMPORTANT
            )
            .rrShadow()
    }
}

/// Main guided-flow screen. Hosts the AR visual panel on the left and the step card
/// on the right (iPad/landscape) or stacked vertically (iPhone/compact). Manages
/// navigation between rescue steps, safety checklists, voice assist, and AR session.
struct FlowScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            contentArea
        }
        .safeAreaInset(edge: .bottom) {
            bottomDock
                .padding(.bottom, 10) // Lift it slightly off the bottom edge
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
            // Restore any previously saved choice and kick off voice assist on first display
            if let saved = choiceMemory[engine.currentStep.id] {
                selectedChoiceID = saved
            } else {
                selectedChoiceID = nil
            }
            if voiceAssistEnabled {
                speech.speak(speechText)
            }
            if engine.currentStep.id == "ft_tools" {
                toolsChecks = Array(repeating: false, count: toolsItems.count)
            }
            if voiceControlEnabled {
                startVoiceCommands()
            }
        }
        .onChange(of: engine.currentStep.id) {
            // Sync choice selection and voice assistant whenever the step changes
            if let saved = choiceMemory[engine.currentStep.id] {
                selectedChoiceID = saved
            } else {
                selectedChoiceID = nil
            }
            // Reset tools checklist every time we enter the tools step
            if engine.currentStep.id == "ft_tools" {
                toolsChecked.removeAll()
            }
            if engine.currentStep.id == "ft_tools" {
                toolsChecks = Array(repeating: false, count: toolsItems.count)
            }
            if voiceAssistEnabled {
                speech.speak(speechText)
            }
            if engine.currentStep.id == engine.stepsInOrder.last?.id {
                showCompletion = true
            }
        }
        .onDisappear {
            voiceCommands.stop()
        }
    }
    
    @Environment(\.horizontalSizeClass) private var hSize
    
    // MARK: - Dependencies & State
    @ObservedObject var engine: FlowEngine   // drives step navigation and mode
    let onOpenArticles: () -> Void           // callback to open the Articles tab
    @State private var showSections = false  // toggles the step-list sheet
    @State private var safetyChecks: [Bool] = Array(repeating: false, count: 4)  // 4 safety pre-checks (ft_safety step)
    @State private var toolsChecked: Set<String> = []   // tracks checked tool names (unused path)
    @State private var toolsChecks: [Bool] = []          // per-item check state for tools checklist
    @State private var toolChecks: [Bool] = Array(repeating: false, count: 5)  // legacy 5-item tool checks
    @State private var selectedChoiceID: String? = nil   // which branch choice is selected
    @State private var choiceMemory: [String: String] = [:]  // persists choices per step ID
    
    @State private var cameraEverOpened = false      // true once user taps "Start AR Camera"
    @State private var showARLugSetup = false         // controls the inline lug-count slider
    @StateObject private var arSession = ARSessionModel()
    @AppStorage("lugCount") private var lugCount: Int = 5           // persisted lug nut count
    @AppStorage("voiceAssistEnabled") private var voiceAssistEnabled: Bool = false   // audio TTS toggle
    @AppStorage("voiceControlEnabled") private var voiceControlEnabled: Bool = false // voice command toggle
    @StateObject private var speech = SpeechController()
    @StateObject private var voiceCommands = VoiceCommandController()
    @State private var lastVoiceNavAt: TimeInterval = 0   // timestamp of last voice-triggered navigation
    private let voiceNavCooldown: TimeInterval = 0.9      // minimum seconds between voice nav commands
    private let voiceControlInstructionsText =
    "Voice help. With Voice Control, you can say: Tap Next, or Tap Back. With VoiceOver, swipe to navigate and double-tap to activate."
    
    @State private var showCompletion = false
    @State private var showLugSetup = false
    @State private var pendingLugCount: Int = 5
    
    // Maps each flat-tire step ID to the matching hero image asset name
    private let flatTireHeroMap: [String: String] = [
        "ft_safety": "hero_safety",
        "ft_tools": "hero_tire",
        "ft_spare_check": "hero_spare",
        "ft_chock": "hero_chock",
        "ft_loosen": "hero_lugs",
        "ft_jackpoint": "hero_jack",
        "ft_jackup": "hero_jack",
        "ft_remove": "hero_lugs",
        "ft_mount": "hero_tire",
        "ft_lower": "hero_jack",
        "ft_aftercare": "hero_tire",
    ]
    
    // Returns the correct hero image name for the current mode and step
    private var heroAssetName: String {
        if engine.mode == .flatTire {
            return flatTireHeroMap[engine.currentStep.id] ?? "hero_tire"
        } else {
            return "hero_battery"
        }
    }
    
    // Returns safety warning chips shown on steps with physical hazards
    private func heroTags(for stepID: String) -> [String] {
        switch stepID {
        case "ft_jackpoint", "ft_jackup":
            return ["Pinch points", "Heavy load"]
        default:
            return []
        }
    }
    
    // Overrides the engine's step title for steps that need friendlier display names
    private var displayTitle: String {
        if engine.currentStep.id == "ft_safety" {
            return "Flat Tire Fix"
        }
        if engine.currentStep.id == "ft_tools" {
            return "Required Tools"
        }
        return engine.currentStep.title
    }
    
    // Maps each flat-tire step to an SF Symbol or asset name used in the hero/sections list
    private func stepSymbol(for mode: RescueMode, stepID: String) -> String {
        guard mode == .flatTire else { return "bolt.car.fill" }
        switch stepID {
        case "ft_safety":      return "hero_tire"
        case "ft_tools":       return "wrench.and.screwdriver"
        case "ft_spare_check": return "hero_spare"
        case "ft_chock":       return "hero_chock"
        case "ft_loosen":      return "hero_lugs"
        case "ft_jackpoint":   return "location.north.circle"
        case "ft_jackup":      return "arrow.up.to.line.circle"
        case "ft_remove":      return "hero_lugs"
        case "ft_mount":       return "arrow.left.circle"
        case "ft_lower":       return "arrow.down.to.line.circle"
        case "ft_aftercare":   return "checkmark.seal"
        default:               return "info.circle"
        }
    }
    
    // Parses the step body text into a list of bullet-point tool names for the checklist
    private var toolsItems: [String] {
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
    
    // Renders a tappable checklist row for a required tool with an icon, title, and optional subtitle
    private func toolRow(symbol: String, title: String, subtitle: String? = nil, index: Int) -> some View {
        Button {
            toolChecks[index].toggle()
        } label: {
            HStack(spacing: 12) {
                
                Image(systemName: toolChecks[index] ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(toolChecks[index] ? Color.accentColor : Color.white.opacity(0.3))
                
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(rrPanelSecondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(rrPanelSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // The right-panel content shown during the ft_tools step: lists all 5 required tools
    private var toolsRightPanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Required Tools")
                    .font(.title3.weight(.semibold))
                
                Text("Verify your equipment before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(rrPanelSecondary)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                // If SF Symbol 'tire' is unavailable on your SDK, replace with 'circle.hexagonpath'
                toolRow(symbol: "tire", title: "Spare tire (or donut)", index: 0)
                Divider().opacity(0.3)
                
                toolRow(symbol: "arrow.up.square", title: "Jack", index: 1)
                Divider().opacity(0.3)
                
                toolRow(symbol: "wrench", title: "Lug wrench", index: 2)
                Divider().opacity(0.3)
                
                toolRow(symbol: "square.fill", title: "Wheel chock", index: 3)
                Divider().opacity(0.3)
                
                toolRow(symbol: "flashlight.off.fill", title: "Flashlight + gloves", subtitle: "Optional", index: 4)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            
            Spacer()
        }
    }
    
    // Builds a clean spoken version of the current step for TTS — strips arrows, bullets, etc.
    private var speechText: String {
        let cleanedBody = engine.currentStep.body
            .replacingOccurrences(of: "→", with: " to ")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "–", with: " to ")
            .replacingOccurrences(of: "(+)", with: " positive ")
            .replacingOccurrences(of: "(-)", with: " negative ")
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
    
    // True once all 4 safety items are checked (or if we're past that step)
    private var safetyReady: Bool {
        engine.currentStep.id != "ft_safety" || safetyChecks.allSatisfy { $0 }
    }
    
    // True once the AR guide is aligned (or if the current step doesn't require AR alignment)
    private var alignmentReady: Bool {
        engine.currentStep.id != "ft_align" || arSession.isAligned
    }
    
    // Looks up the currently selected choice object from the engine's step choices
    private var selectedChoice: RescueChoice? {
        guard let id = selectedChoiceID else { return nil }
        return engine.currentStep.choices.first { $0.id == id }
    }
    
    // True when the user has satisfied all requirements to move forward
    private var canAdvanceFromStep: Bool {
        engine.currentStep.choices.isEmpty ? engine.canGoNext : (selectedChoice != nil)
    }
    
    // True when the Next button should be tappable (choice or linear step)
    private var canTapNext: Bool {
        if !engine.currentStep.choices.isEmpty { return true }
        return engine.canGoNext
    }
    
    // True when this is the very first step (no back navigation possible)
    private var isFirstScreen: Bool { !engine.canGoBack }
    
    // Whether the Continue button on the first screen should be enabled
    // (requires all safety checks on the ft_safety step)
    private var firstContinueEnabled: Bool {
        if isFirstScreen && engine.currentStep.id == "ft_safety" {
            return safetyChecks.allSatisfy { $0 }
        }
        return engine.canGoNext || !engine.currentStep.choices.isEmpty
    }
    
    // Thin capsule divider used between the visual panel and step card (iPad side-by-side layout)
    private var panelDividerVertical: some View {
        Capsule()
            .fill(Color.black.opacity(0.08))
            .frame(width: 6)
            .padding(.vertical, 28)
    }
    
    // Thin capsule divider used between panels stacked vertically (iPhone layout)
    private var panelDividerHorizontal: some View {
        Capsule()
            .fill(Color.black.opacity(0.08))
            .frame(height: 6)
            .padding(.horizontal, 28)
    }
    
    // Sheet that lists all steps in the current rescue flow with a checkmark on the active step
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
    
    // Accent-colored pill showing current step progress (e.g. "Step 3 of 8")
    private var stepPill: some View {
        Text(engine.progressText)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .rrPillShadow()
    }
    
    // Pill button to toggle TTS audio instructions on/off
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
            .foregroundStyle(.white) // ✅ always white text
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(white: 0.15), in: Capsule()) // ✅ dark gray
        }
        .buttonStyle(.plain)
        .rrPillShadow()
    }
    
    // Pill button to toggle voice command recognition ("Tap Next", "Tap Back")
    private var voiceControlPill: some View {
        Button {
            speech.stop()
            voiceControlEnabled.toggle()
            if voiceControlEnabled {
                startVoiceCommands()
                speech.speak(voiceControlInstructionsText)
            } else {
                voiceCommands.stop()
                speech.speak("Voice control off")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceControlEnabled ? "mic.fill" : "mic.slash.fill")
                Text("Voice Control")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white) // ✅ always white text
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(white: 0.15), in: Capsule()) // ✅ dark gray
        }
        .buttonStyle(.plain)
        .rrPillShadow()
    }
    
    // Returns the contextual instruction text shown in the floating pill at the top of the AR panel,
    // guiding the user through placement, lug setup, and per-step AR hints
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
    
    // Current AR status phase (none / resetting / ready) used to show spinner or checkmark in the pill
    private var arTopPhase: ARSessionModel.StatusPhase {
        arSession.statusPhase
    }
    
    // Renders the floating AR status pill with optional spinner (resetting) or checkmark (ready)
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
    
    // True when the user has placed the AR anchor but hasn't confirmed lug count yet
    private var shouldShowARLugContinue: Bool {
        cameraEverOpened &&
        arSession.hasAnchor &&
        !arSession.lugSetupConfirmed &&
        !showARLugSetup
    }
    
    // "Continue" pill shown after AR placement to prompt the user to set their lug count
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
    
    // Inline slider pill for choosing lug count (5–8) directly inside the AR panel
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
                        arSession.confirmLugSetup(lugCount)
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
    
    // True when the lug-edit entry button should be shown (anchor placed, confirmed, slider hidden)
    private var showARLugEntry: Bool {
        cameraEverOpened && arSession.hasAnchor && arSession.isLocked && !showARLugSetup
    }
    
    // Shows current lug count with an "Edit" affordance, or "Continue" if not yet confirmed
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
    
    // Placeholder card shown before the camera is opened, prompting the user to start AR
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
    
    // FlowScreen.swift
    
    private var visualPanel: some View {
        ZStack {
            // High-contrast deep dark glass backing
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.85)) // Darker for better contrast
            
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
        // ✅ APPLY THE GLASS MODIFIER HERE FOR GLOSS & BORDERS
        .rrGlassCard(cornerRadius: 22)
        .overlay(alignment: .topLeading) {
            if cameraEverOpened {
                Button { arSession.requestReset() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset AR")
                    }
                    .font(.subheadline.weight(.medium))
                    .tracking(0.2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
    }
    
    // The glass card containing the step header, hero image, body content, and choice selectors
    private var stepCard: some View {
        stepCardContent
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .rrGlassCard(cornerRadius: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.2)
                    .allowsHitTesting(false) // ✅ add this
            )
        
    }
    // Primary "Listen / Stop audio" button displayed inside the step card body
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
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speech.isSpeaking ? "Stop audio" : "Play audio")
    }
    
    // UPDATED HERO: Supports side-by-side icons for prep steps in the header
    private struct InstructionHero: View {
        let stepID: String
        let symbol: String
        let title: String
        
        var body: some View {
            VStack(spacing: 14) {
                HStack(spacing: 28) {
                    if stepID == "ft_tools" {
                        Image("hero_tools")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 130)
                    } else if stepID == "ft_jackpoint" {
                        // Side-by-side icons for the jack point step
                        Image("hero_jack1")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                        
                        Image("hero_jack2")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                    } else if stepID == "ft_jackup" {
                        // Side-by-side icons for the lift car step
                        Image("hero_lift1")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                        
                        Image("hero_lift2")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                    } else if stepID == "ft_loosen" {
                        // Side-by-side icons for the loosen lugs step
                        Image("hero_lugs")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                        
                        Image("hero_lugs2")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                    } else if stepID == "ft_mount" {
                        // Side-by-side icons for the mount spare step
                        Image("hero_spare")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                        
                        Image("hero_spare2")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                    } else if stepID == "ft_lower" {
                        // Side-by-side icons for the lower car step
                        Image("hero_lower1")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                        
                        Image("hero_lower2")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 90)
                    } else {
                        if UIImage(named: symbol) != nil {
                            Image(symbol)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 110)
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 84, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .rrStepTitleOnGlass()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
                .foregroundStyle(rrPanelSecondary)
            Text(s)
                .font(.body)
                .foregroundStyle(rrPanelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // Full content stack for the step card: progress pill, hero, divider, and step-specific body
    private var stepCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Progress pill on left, audio/voice on right
            HStack(spacing: 8) {
                stepPill
                Spacer()
                voiceControlPill
                audioInstructionsPill
            }
            
            InstructionHero(
                stepID: engine.currentStep.id,
                symbol: stepSymbol(for: engine.mode, stepID: engine.currentStep.id),
                title: displayTitle
            )
            
            
            Divider()
            
            if engine.currentStep.id == "ft_safety" {
                VStack(alignment: .leading, spacing: 12) {
                    SafetyAdvisoryCard(text: "If you’re in danger, call local emergency services.")
                    VoiceAssistCard(action: { speech.toggle(speechText) })
                    
                    Text("Safety check. Tap each item to confirm.")
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
                            .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                Spacer(minLength: 0)
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
        
        .foregroundStyle(rrPanelPrimary)
    }
    
    // Renders up to 2 branching choice buttons (primary style for selected, secondary for unselected)
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
    
    // Lays out the visual panel and step card side-by-side (iPad/regular) or stacked (iPhone/compact)
    private var contentArea: some View {
        GeometryReader { geo in
            Group {
                if hSize == .regular {
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
                    let spacing: CGFloat = 12
                    let isLandscape = geo.size.width > geo.size.height
                    let ratio: CGFloat = isLandscape ? 0.55 : 0.35
                    
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
    
    // Floating bottom dock: navigation buttons stacked above the step progress indicator
    private var bottomDock: some View {
        VStack(spacing: 24) {
            // Navigation Buttons
            Group {
                if engine.canGoBack {
                    bottomNavRow
                } else {
                    bottomContinueRow
                }
            }
            .frame(maxWidth: 320)
            
            // The Floating Glossy Progress Indicator
            HStack {
                Spacer(minLength: 0)
                StepProgressIndicator(
                    steps: engine.stepsInOrder,
                    currentStepID: engine.currentStep.id,
                    mode: engine.mode
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.15), Color(white: 0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.9)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .rrShadow()
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear) // ❌ Kills the white box ❌
    }
    // "Continue" button shown on the very first step (no Back available yet)
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
            .accessibilityLabel("Continue")
            .buttonStyle(RRPrimaryPillButtonStyle())
            .frame(width: 320, height: 48)
            .disabled(!firstContinueEnabled)
            Spacer(minLength: 0)
        }
        
    }
    
    // Back + Next button pair shown on all steps after the first
    private var bottomNavRow: some View {
        HStack(spacing: 12) {
            Button("Back") { engine.goBack() }
                .accessibilityHint("Go to the previous step")
                .accessibilityLabel("Back")
                .buttonStyle(RRSecondaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!engine.canGoBack)
            
            Button("Next") { handleNext() }
                .accessibilityHint("Go to the next step")
                .accessibilityLabel("Next")
                .buttonStyle(RRPrimaryPillButtonStyle())
                .frame(width: 160, height: 48)
                .disabled(!canTapNext)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    // Starts the voice command listener and wires "next", "back", "repeat", and "stop" commands
    // with a cooldown to prevent accidental rapid navigation
    private func startVoiceCommands() {
        voiceCommands.start { command in
            let now = Date().timeIntervalSince1970
            guard now - lastVoiceNavAt > voiceNavCooldown else { return }
            switch command {
            case .next:
                if canTapNext { lastVoiceNavAt = now; handleNext() }
            case .back:
                if engine.canGoBack { lastVoiceNavAt = now; engine.goBack() }
            case .repeatStep:
                speech.stop()
                speech.speak(speechText)
            case .stop:
                voiceCommands.stop()
                voiceControlEnabled = false
                speech.speak("Voice control off")
            }
        }
    }
    
    // Advances the engine: resolves the selected choice if present, otherwise goes to the next step
    private func handleNext() {
        if !engine.currentStep.choices.isEmpty {
            let choice = selectedChoice ?? engine.currentStep.choices.first!
            engine.select(choice)
            return
        }
        
        engine.goNext()
    }
    
}

/// Filled accent-color capsule button — used for the primary "Next" / "Continue" action
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
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.2) // ← white outline
            )
            .rrShadow()
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Secondary (unfilled) capsule button — used for the "Back" action and unselected choices
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

/// Small grey capsule chip used to display safety tags (e.g. "Pinch points") on hero images
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

/// Tappable row with a checkbox, title, and subtitle — used in the safety pre-check list
private struct ChecklistRow: View {
    let title: String
    let subtitle: String
    @Binding var isChecked: Bool
    
    var body: some View {
        Button { isChecked.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.white.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(rrPanelSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tappable row with an icon, title, and checkbox — used in the required-tools checklist
private struct ToolRow: View {
    let icon: String
    let title: String
    @Binding var isChecked: Bool
    
    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.white.opacity(0.3))
                
                Text(icon)
                
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Red-icon advisory banner shown at the top of the safety step ("call emergency services")
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
                    .foregroundStyle(rrPanelSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

/// Tappable info card that explains voice assistant options and plays the current step when tapped
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
                    .fill(Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.72))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice Assistant. Tap to hear instructions. Use VoiceOver to read steps aloud. With Voice Control, say Tap Next or Tap Back.")
        .accessibilityHint("Plays the current step instructions.")
    }
}

/// Fallback view shown in the AR panel when running in Simulator (no camera available)
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

/// Sheet shown when the user reaches the last step — offers "View Articles" and "Restart guide"
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

/// Sheet for selecting lug nut count (5–8) before AR begins — persists choice and confirms to AR session
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
