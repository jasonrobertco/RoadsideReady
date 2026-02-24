import Foundation
import Combine
import simd

@MainActor
final class ARSessionModel: ObservableObject {
    @Published var wheelTransform: simd_float4x4? = nil
    @Published var isAligned: Bool = false

    var hasAnchor: Bool { wheelTransform != nil }

    func setAnchor(_ transform: simd_float4x4) {
        wheelTransform = transform
        isAligned = true
    }

    func reset() {
        wheelTransform = nil
        isAligned = false
    }
}
