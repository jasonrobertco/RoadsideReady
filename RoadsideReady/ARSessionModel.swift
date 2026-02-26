// ARSessionModel.swift

import Combine
import simd

@MainActor
final class ARSessionModel: ObservableObject {
    enum StatusPhase { case none, resetting, ready }

    @Published var wheelTransform: simd_float4x4? = nil
    @Published var isAligned: Bool = false
    @Published var isLocked: Bool = false

    @Published var expectedLugCount: Int = 5
    @Published var loosenedLugs: Set<Int> = []

    // Redo button trigger (ARViewContainer watches this)
    @Published var resetRequest: Int = 0
    @Published var statusText: String? = nil
    @Published var statusPhase: StatusPhase = .none

    var hasAnchor: Bool { wheelTransform != nil }

    func setAnchor(_ transform: simd_float4x4) {
        wheelTransform = transform
        isAligned = true
        isLocked = false
    }

    func lock()   { if hasAnchor { isLocked = true } }
    func unlock() { isLocked = false }

    // CRITICAL: idempotent to avoid update loops
    func setExpectedLugCount(_ n: Int) {
        let v = max(3, min(10, n))
        guard v != expectedLugCount else { return }
        expectedLugCount = v
        loosenedLugs = loosenedLugs.filter { $0 < expectedLugCount }
    }

    func toggleLoosened(_ idx: Int) {
        guard idx >= 0 && idx < expectedLugCount else { return }
        if loosenedLugs.contains(idx) { loosenedLugs.remove(idx) }
        else { loosenedLugs.insert(idx) }
    }

    func resetLugs() { loosenedLugs.removeAll() }

    func resetAlignment() {
        wheelTransform = nil
        isAligned = false
        isLocked = false
        loosenedLugs.removeAll()
    }

    func setStatus(_ text: String?, phase: StatusPhase = .none) {
        statusText = text
        statusPhase = phase
    }

    func requestReset() {
        resetRequest &+= 1
        setStatus("Resetting AR…", phase: .resetting)
    }
}
