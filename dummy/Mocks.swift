/*import SwiftUI
import Combine

// MARK: - AR Stubs (so FlowScreen compiles without ARKit)

struct ARViewContainer: View {
    var body: some View { Color.clear }
}

final class ARSessionModel: ObservableObject {
    
    enum StatusPhase { case none, resetting, ready }
    
    // Match what FlowScreen reads
    @Published var statusText: String? = nil
    @Published var statusPhase: StatusPhase = .none
    @Published var lugSetupConfirmed: Bool = false
    @Published var isLocked: Bool = false
    @Published var isAligned: Bool = false
    
    var hasAnchor: Bool { false }
    var resetRequest: Int { 0 }
    
    // Match what FlowScreen calls
    func requestReset() { statusPhase = .resetting }
    func setExpectedLugCount(_ n: Int) {}
    func confirmLugSetup(_ n: Int) { lugSetupConfirmed = true }
    func resetAlignment() { isAligned = false; isLocked = false }
    
    func lock() { isLocked = true }
    func unlock() { isLocked = false }
}*/
