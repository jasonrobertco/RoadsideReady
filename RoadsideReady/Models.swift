//
//  Models.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import Foundation

enum RescueMode: String, CaseIterable, Identifiable {
    case flatTire = "Flat Tire"
    case deadBattery = "Dead Battery"
    var id: String { rawValue }
}

enum SafetyFlag: String, CaseIterable, Identifiable {
    case traffic = "Traffic safety"
    case pinchPoints = "Pinch points"
    case heavyLift = "Heavy load"
    case sparks = "Sparks risk"
    case chemicals = "Battery acid"
    case stopIfUnsure = "Stop if unsure"

    var id: String { rawValue }
}

struct RescueChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let nextStepID: String
}

struct RescueStep: Identifiable {
    let id: String
    let title: String
    let body: String
    let safety: [SafetyFlag]

    // Linear flow: if non-nil and choices is empty, Next goes here.
    let nextStepID: String?

    // Branching flow: if non-empty, user must pick one.
    let choices: [RescueChoice]
}

struct RescueFlow {
    let mode: RescueMode
    let startStepID: String
    let stepsInOrder: [RescueStep]
}
