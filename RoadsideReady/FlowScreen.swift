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
    @State private var isAligned = false
    @State private var safetyChecks: [Bool] = Array(repeating: false, count: 4)
    @State private var showAR = false
    @State private var showScan = false

    private let progressBarHeight: CGFloat = 56
    
    private var safetyReady: Bool {
        engine.currentStep.id != "ft_safety" || safetyChecks.allSatisfy { $0 }
    }

    private var alignmentReady: Bool {
        engine.currentStep.id != "ft_align" || isAligned
    }

    private var canProceed: Bool {
        engine.canGoNext && safetyReady && alignmentReady
    }


    var body: some View {
        VStack(spacing: 12) {
            if engine.currentStep.id != "ft_safety" { headerRow }
            stepCard
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
            if engine.mode == .flatTire {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScan = true } label: {
                        Image(systemName: "camera")
                    }
                    .accessibilityLabel("Open scan")
                }
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanPlaceholderView()
        }
        .fullScreenCover(isPresented: $showAR) {
            ARFullScreenView(currentStepID: engine.currentStep.id, isAligned: $isAligned)
        }
        .onChange(of: engine.currentStep.id) { _, newID in
            if newID == "ft_safety" { safetyChecks = Array(repeating: false, count: 4) }
            if newID != "ft_align" { isAligned = false }
        }
    }
    
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if engine.currentStep.id == "ft_safety" {
                Button("Continue") {
                    guard safetyReady else { return }
                    engine.goNext()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!safetyReady)
            } else if engine.currentStep.choices.isEmpty {
                HStack(spacing: 12) {
                    Button("Back") { engine.goBack() }
                        .buttonStyle(.bordered)
                        .disabled(!engine.canGoBack)
                    Spacer()
                    Button(engine.canGoNext ? "Next" : "Done") {
                        guard canProceed else { return }
                        engine.goNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
                }
            }

            StepProgressIndicator(
                steps: engine.stepsInOrder,
                currentStepID: engine.currentStep.id,
                mode: engine.mode
            )
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .ignoresSafeArea(.container, edges: .horizontal)
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            bottomActions

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
    
    @ViewBuilder
    private var bottomActions: some View {
        if engine.currentStep.id == "ft_safety" {
            safetyProceedButton
        } else if !engine.currentStep.choices.isEmpty {
            choiceButtons
        } else {
            navButtons
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 10) {
            Text(engine.mode == .flatTire ? "Flat Tire" : "Dead Battery")
                .font(.headline)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
                Image(systemName: engine.mode == .flatTire ? "tirepressure" : "battery.0")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var safetyAdvisoryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safety advisory")
                    .font(.subheadline.weight(.semibold))
                Text("If you’re in danger, call local emergency services.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var safetyChecklistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Safety check").font(.title2.weight(.bold))
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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            Text("In an emergency, call local emergency services.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
    }
    

    private var shouldShowCameraLauncher: Bool {
        engine.mode == .flatTire && engine.currentStep.id != "ft_safety" && ["ft_align", "ft_loosen"].contains(engine.currentStep.id)
    }

    
    private var cameraLauncher: some View {
        Button {
            showAR = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Camera")
                        .font(.headline)

                    Text(isAligned ? "Wheel aligned" : "Camera off • Tap to align wheel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero (centered) + Scan pill (top-right)
    private var safetyHeroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(height: 170)

            VStack(spacing: 10) {
                Text("Flat Tire")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Placeholder hero icon (replace later with your tire illustration)
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
                    .frame(width: 92, height: 92)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .overlay {
            ScanBoxButton {
                showAR = true
            }
            .frame(maxWidth: 420)
            .padding(24)
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


    private var stepCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            if engine.currentStep.id != "ft_safety" {
                // Title
                Text(engine.currentStep.title)
                    .font(.title2.weight(.bold))
            }

            // Safety step: simplified checklist layout
            if engine.currentStep.id == "ft_safety" {
                VStack(alignment: .leading, spacing: 12) {

                    safetyHeroCard

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
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
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


    private var navButtons: some View {
        HStack(spacing: 10) {
            Button("Back") { engine.goBack() }
                .buttonStyle(.bordered)
                .disabled(!engine.canGoBack)

            Spacer()

            Button(engine.canGoNext ? "Next" : "Done") {
                guard canProceed else { return }
                engine.goNext()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed)
        }
    }
    
    private var safetyProceedButton: some View {
        Button(safetyReady ? "Continue" : "Check") {
            guard safetyReady else { return }
            engine.goNext()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(!safetyReady)
    }


    private var choiceButtons: some View {
        VStack(spacing: 12) {
            ForEach(engine.currentStep.choices) { choice in
                Button(choice.title) {
                    engine.select(choice)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }

            if engine.canGoBack {
                Button("Back") { engine.goBack() }
                    .buttonStyle(.bordered)
            }
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

private struct FlatTireInfographic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemBackground))

            HStack(spacing: 14) {
                ZStack {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.secondary)

                    // “flat tire” emphasis (simple highlight)
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: 18, height: 18)
                        .offset(x: -18, y: 14)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Safety first")
                        .font(.headline)
                    Text("Complete the checks before continuing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
        }
        .frame(height: 92)
    }
}

private struct ScanBoxButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background card
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.black.opacity(0.08), lineWidth: 1)
                    )

                // Content
                VStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 30, weight: .semibold))

                    Text("Scan")
                        .font(.headline)

                    Text("Point the camera at the marker")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            // Make it vertically dominant: portrait-ish 2:3 ratio
            .aspectRatio(2.0/3.0, contentMode: .fit)
            .frame(minHeight: 160) // sensible floor on small phones
        }
        .buttonStyle(.plain)
    }
}

private struct SafetyHeroHeader: View {
    let onScan: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(height: 180)

            VStack(spacing: 10) {
                Text("Flat Tire")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 86, height: 86)

                    Image(systemName: "tirepressure")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            Button(action: onScan) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(12)
        }
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

private struct ScanPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 54, weight: .semibold))
                    .padding(.top, 40)

                Text("Scan (placeholder)")
                    .font(.title2.weight(.bold))

                Text("Later, this will scan a QR code on a wheel marker to align the overlay.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

