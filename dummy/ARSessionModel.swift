// ARSessionModel.swift

import Foundation
import Combine
import simd

final class ARSessionModel: ObservableObject {
    enum StatusPhase { case none, resetting, ready }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() }
        else { DispatchQueue.main.async(execute: block) }
    }

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
        onMain {
            self.wheelTransform = transform
            self.isAligned = true
            self.isLocked = false

            self.lugSetupConfirmed = false
            self.expectedLugCount = max(5, min(8, self.expectedLugCount))

            self.loosenedLugs.removeAll()
            self.tightenedLugs.removeAll()
            self.activeLugIndex = nil
        }
    }

    func lock() {
        onMain { if self.hasAnchor { self.isLocked = true } }
    }
    func unlock() {
        onMain { self.isLocked = false }
    }

    // MARK: - Lug setup

    // Keep this idempotent to avoid SwiftUI update loops
    func setExpectedLugCount(_ n: Int) {
        onMain {
            let v = max(5, min(8, n))
            guard v != self.expectedLugCount else { return }
            self.expectedLugCount = v
            self.loosenedLugs = self.loosenedLugs.filter { $0 < self.expectedLugCount }
            self.tightenedLugs = self.tightenedLugs.filter { $0 < self.expectedLugCount }
            if let a = self.activeLugIndex, a >= self.expectedLugCount { self.activeLugIndex = nil }
        }
    }

    func confirmLugSetup(_ n: Int) {
        onMain {
            self.setExpectedLugCount(n)
            self.lugSetupConfirmed = true
            self.tightenedLugs.removeAll()
            self.activeLugIndex = nil
        }
    }

    // MARK: - Loosen

    func toggleLoosened(_ idx: Int) {
        onMain {
            guard idx >= 0 && idx < self.expectedLugCount else { return }
            if self.loosenedLugs.contains(idx) { self.loosenedLugs.remove(idx) }
            else { self.loosenedLugs.insert(idx) }
        }
    }

    func markLoosened(_ idx: Int) {
        onMain {
            guard idx >= 0 && idx < self.expectedLugCount else { return }
            self.loosenedLugs.insert(idx)
        }
    }

    func resetLugs() { onMain { self.loosenedLugs.removeAll() } }

    // MARK: - Tighten sequence

    func beginTightenSequence() {
        onMain {
            self.tightenedLugs.removeAll()
            self.activeLugIndex = self.tightenOrder().first
        }
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
        onMain {
            guard self.lugSetupConfirmed else { return }
            guard idx >= 0 && idx < self.expectedLugCount else { return }

            if let active = self.activeLugIndex, idx != active {
                self.setStatus("Tap the highlighted lug next.")
                return
            }

            self.tightenedLugs.insert(idx)
            let next = self.tightenOrder().first(where: { !self.tightenedLugs.contains($0) })
            self.activeLugIndex = next

            if next == nil {
                self.setStatus("Sequence complete ✓", phase: .ready)
                self.clearStatus(afterSeconds: 0.8)
            }
        }
    }

    // MARK: - Reset

    func resetAlignment() {
        onMain {
            self.wheelTransform = nil
            self.isAligned = false
            self.isLocked = false

            self.lugSetupConfirmed = false
            self.expectedLugCount = max(5, min(8, self.expectedLugCount))

            self.loosenedLugs.removeAll()
            self.tightenedLugs.removeAll()
            self.activeLugIndex = nil
        }
    }

    // MARK: - Status

    func setStatus(_ text: String?, phase: StatusPhase = .none) {
        onMain {
            self.statusText = text
            self.statusPhase = phase
        }
    }

    func requestReset() {
        onMain {
            self.resetRequest &+= 1
            self.setStatus("Resetting AR…", phase: .resetting)
        }
    }

    private func clearStatus(afterSeconds seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.setStatus(nil, phase: .none)
        }
    }
}

