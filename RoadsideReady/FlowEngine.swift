//
//  FlowEngine.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import Foundation
import SwiftUI
import Combine


@MainActor
final class FlowEngine: ObservableObject {
    @Published private(set) var mode: RescueMode = .flatTire
    @Published private(set) var currentStepID: String

    private(set) var stepsInOrder: [RescueStep] = []
    private var stepsByID: [String: RescueStep] = [:]
    private var indexByID: [String: Int] = [:]

    private var backStack: [String] = []

    init() {
        let flow = Flows.flatTire

        self.currentStepID = flow.startStepID
        self.stepsInOrder = []
        self.stepsByID = [:]
        self.indexByID = [:]

        load(flow: flow)
    }


    var currentStep: RescueStep {
        stepsByID[currentStepID]!
    }

    var canGoBack: Bool { !backStack.isEmpty }

    var canGoNext: Bool {
        let step = currentStep
        if !step.choices.isEmpty { return false }
        return step.nextStepID != nil
    }

    var progressText: String {
        guard let idx = indexByID[currentStepID] else { return "" }
        return "Step \(idx + 1) of \(stepsInOrder.count)"
    }

    func setMode(_ newMode: RescueMode) {
        mode = newMode
        backStack.removeAll()

        let flow: RescueFlow = (newMode == .flatTire) ? Flows.flatTire : Flows.deadBattery
        load(flow: flow)
        currentStepID = flow.startStepID
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        currentStepID = prev
    }

    func goNext() {
        let step = currentStep
        guard step.choices.isEmpty else { return }
        guard let next = step.nextStepID else { return }
        backStack.append(currentStepID)
        currentStepID = next
    }

    func select(_ choice: RescueChoice) {
        backStack.append(currentStepID)
        currentStepID = choice.nextStepID
    }

    func jump(to stepID: String) {
        guard stepsByID[stepID] != nil else { return }
        backStack.append(currentStepID)
        currentStepID = stepID
    }

    private func load(flow: RescueFlow) {
        stepsInOrder = flow.stepsInOrder
        stepsByID = Dictionary(uniqueKeysWithValues: flow.stepsInOrder.map { ($0.id, $0) })
        indexByID = [:]
        for (i, s) in flow.stepsInOrder.enumerated() {
            indexByID[s.id] = i
        }
    }
}

