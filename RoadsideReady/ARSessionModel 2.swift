#if false
import Foundation
import Combine
import simd

@MainActor
final class ARSessionModel: ObservableObject {
    @Published var wheelTransform: simd_float4x4? = nil
    @Published var isAligned: Bool = false
    @Published var isLocked: Bool = false

    // Lug tracking (for ft_loosen)
    @Published var expectedLugCount: Int = 5
    @Published var loosenedLugs: Set<Int> = []

    var hasAnchor: Bool { wheelTransform != nil }

    func setAnchor(_ transform: simd_float4x4) {
        wheelTransform = transform
        isAligned = true
        isLocked = false
    }

    func lock()   { if hasAnchor { isLocked = true } }
    func unlock() { isLocked = false }

    func setExpectedLugCount(_ n: Int) {
        expectedLugCount = max(3, min(10, n))
        loosenedLugs = loosenedLugs.filter { $0 < expectedLugCount }
    }

    func toggleLoosened(_ idx: Int) {
        guard idx >= 0 && idx < expectedLugCount else { return }
        if loosenedLugs.contains(idx) { loosenedLugs.remove(idx) }
        else { loosenedLugs.insert(idx) }
    }

    func resetAlignment() {
        wheelTransform = nil
        isAligned = false
        isLocked = false
        loosenedLugs.removeAll()
    }

    func resetLugs() {
        loosenedLugs.removeAll()
    }
}
#endif
