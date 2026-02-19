//
//  StepProgressIndicator.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/18/26.
//

import SwiftUI

struct StepProgressIndicator: View {
    let steps: [RescueStep]
    let currentStepID: String
    let mode: RescueMode

    private var currentIndex: Int {
        steps.firstIndex(where: { $0.id == currentStepID }) ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(
                value: Double(currentIndex + 1),
                total: Double(max(steps.count, 1))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        StepNode(
                            icon: iconName(for: step),
                            state: state(for: idx)
                        )
                        .accessibilityLabel("Step \(idx + 1): \(step.title)")

                        if idx < steps.count - 1 {
                            Capsule()
                                .fill(connectorColor(from: idx))
                                .frame(width: 18, height: 3)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func state(for idx: Int) -> StepNode.State {
        if idx < currentIndex { return .done }
        if idx == currentIndex { return .current }
        return .upcoming
    }

    private func connectorColor(from idx: Int) -> Color {
        idx < currentIndex ? .accentColor : .gray.opacity(0.25)
    }

    private func iconName(for step: RescueStep) -> String {
        switch step.id {
        // Flat tire
        case "ft_safety": return "shield"
        case "ft_unsafe_stop": return "exclamationmark.triangle"
        case "ft_tools": return "wrench.and.screwdriver"
        case "ft_no_spare": return "xmark.circle"
        case "ft_chock": return "car"
        case "ft_loosen": return "wrench.adjustable"
        case "ft_jackpoint": return "location.north"
        case "ft_jackup": return "arrow.up"
        case "ft_remove": return "minus.circle"
        case "ft_mount": return "plus.circle"
        case "ft_lower": return "arrow.down"
        case "ft_aftercare": return "checkmark.seal"

        // Dead battery
        case "db_overview": return "battery.0"
        case "db_safety": return "shield"
        case "db_quickchecks": return "bolt"
        case "db_inspect": return "magnifyingglass"
        case "db_jumpchecklist": return "list.bullet"
        case "db_jumpsteps": return "link"
        case "db_afterstart": return "play.circle"
        case "db_callhelp": return "phone"

        default:
            return (mode == .flatTire) ? "wrench" : "battery.100"
        }
    }
}

private struct StepNode: View {
    enum State { case done, current, upcoming }

    let icon: String
    let state: State

    private var size: CGFloat { state == .current ? 28 : 24 }

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .overlay(
                    Circle().stroke(borderColor, lineWidth: 2)
                )
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var fillColor: Color {
        switch state {
        case .done: return .accentColor
        case .current: return .accentColor.opacity(0.18)
        case .upcoming: return .clear
        }
    }

    private var borderColor: Color {
        switch state {
        case .done: return .accentColor
        case .current: return .accentColor
        case .upcoming: return .gray.opacity(0.35)
        }
    }

    private var iconColor: Color {
        switch state {
        case .done: return .white
        case .current: return .accentColor
        case .upcoming: return .gray.opacity(0.6)
        }
    }
}
