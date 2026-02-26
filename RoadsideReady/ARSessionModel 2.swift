// ARSessionModel.swift

import Foundation
import Combine
import simd

@MainActor
final class ARSessionModel: ObservableObject {
    enum StatusPhase { case none, resetting, ready }

    // Anchor placement
    @Published var wheelTransform: simd_float4x4? = nil
    @Published var isAligned: Bool = false
    @Published var isLocked: Bool = false

    // Lug setup + progress
    @Published var expectedLugCount: Int = 5
    @Published var lugSetupConfirmed: Bool = false

    // Loosen step (user confirms each lug loosened)
    @Published var loosenedLugs: Set<Int> = []

    // Tighten sequence steps
    @Published var tightenedLugs: Set<Int> = []
    @Published var activeLugIndex: Int? = nil

    // Redo trigger (ARViewContainer watches this)
    @Published var resetRequest: Int = 0

    // Inline status pill (used by FlowScreen)
    @Published var statusText: String? = nil
    @Published var statusPhase: StatusPhase = .none

    var hasAnchor: Bool { wheelTransform != nil }

    // MARK: - Placement / locking

    func setAnchor(_ transform: simd_float4x4) {
        wheelTransform = transform
        isAligned = true
        isLocked = false

        // New placement => require setup again
        lugSetupConfirmed = false
        expectedLugCount = max(5, min(8, expectedLugCount))

        loosenedLugs.removeAll()
        tightenedLugs.removeAll()
        activeLugIndex = nil
    }

    func lock()   { if hasAnchor { isLocked = true } }
    func unlock() { isLocked = false }

    // MARK: - Lug setup

    // Keep this idempotent to avoid SwiftUI update loops
    func setExpectedLugCount(_ n: Int) {
        let v = max(5, min(8, n))
        guard v != expectedLugCount else { return }
        expectedLugCount = v

        loosenedLugs = loosenedLugs.filter { $0 < expectedLugCount }
        tightenedLugs = tightenedLugs.filter { $0 < expectedLugCount }

        if let active = activeLugIndex, active >= expectedLugCount {
            activeLugIndex = nil
        }
    }

    func confirmLugSetup(_ n: Int) {
        setExpectedLugCount(n)
        lugSetupConfirmed = true

        // Setup confirmation resets tighten progress (loosen progress is separate)
        tightenedLugs.removeAll()
        activeLugIndex = nil
    }

    // MARK: - Loosen

    func toggleLoosened(_ idx: Int) {
        guard idx >= 0 && idx < expectedLugCount else { return }
        if loosenedLugs.contains(idx) { loosenedLugs.remove(idx) }
        else { loosenedLugs.insert(idx) }
    }

    func resetLugs() { loosenedLugs.removeAll() }

    // MARK: - Tighten sequence

    func beginTightenSequence() {
        tightenedLugs.removeAll()
        activeLugIndex = tightenOrder().first
    }

    /// Star-pattern order (supports 5–8; also works for 7)
    func tightenOrder() -> [Int] {
        let n = expectedLugCount
        guard n >= 3 else { return Array(0..<n) }

        if n % 2 == 0 {
            // even: 0, n/2, 1, n/2+1, ...
            let half = n / 2
            var out: [Int] = []
            out.reserveCapacity(n)
            for i in 0..<half {
                out.append(i)
                out.append(i + half)
            }
            return out
        } else {
            // odd: step by 2 modulo n => star
            var out: [Int] = []
            out.reserveCapacity(n)
            var seen = Set<Int>()
            var i = 0
            while out.count < n {
                if !seen.contains(i) {
                    out.append(i)
                    seen.insert(i)
                }
                i = (i + 2) % n
            }
            return out
        }
    }

    func handleTightenTap(_ idx: Int) {
        guard lugSetupConfirmed else { return }
        guard idx >= 0 && idx < expectedLugCount else { return }

        if let active = activeLugIndex, idx != active {
            setStatus("Tap the highlighted lug next.")
            return
        }

        tightenedLugs.insert(idx)

        let next = tightenOrder().first(where: { !tightenedLugs.contains($0) })
        activeLugIndex = next

        if next == nil {
            setStatus("Sequence complete ✓", phase: .ready)
            clearStatus(afterSeconds: 0.8)
        }
    }

    // MARK: - Reset

    func resetAlignment() {
        wheelTransform = nil
        isAligned = false
        isLocked = false

        lugSetupConfirmed = false
        expectedLugCount = max(5, min(8, expectedLugCount))

        loosenedLugs.removeAll()
        tightenedLugs.removeAll()
        activeLugIndex = nil
    }

    // MARK: - Status

    func setStatus(_ text: String?, phase: StatusPhase = .none) {
        statusText = text
        statusPhase = phase
    }

    func requestReset() {
        resetRequest &+= 1
        setStatus("Resetting AR…", phase: .resetting)
    }

    private func clearStatus(afterSeconds seconds: Double) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self.setStatus(nil, phase: .none)
        }
    }
}
