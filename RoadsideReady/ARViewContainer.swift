import SwiftUI
import UIKit
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    let currentStepID: String
    @ObservedObject var sessionModel: ARSessionModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.attach(arView)
        context.coordinator.restoreAnchorIfNeeded()
        context.coordinator.applyOverlay(for: currentStepID)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // If user reset alignment from SwiftUI, remove anchor.
        if !sessionModel.hasAnchor {
            context.coordinator.clearAnchor()
            context.coordinator.lastStepID = nil
            return
        }

        context.coordinator.restoreAnchorIfNeeded()
        context.coordinator.applyOverlay(for: currentStepID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionModel: sessionModel)
    }

    final class Coordinator: NSObject {
        private let sessionModel: ARSessionModel
        weak var arView: ARView?

        var wheelAnchor: AnchorEntity?
        var lastStepID: String?

        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
        }

        func attach(_ arView: ARView) { self.arView = arView }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }

            let location = sender.location(in: arView)
            let results = arView.raycast(from: location,
                                         allowing: .estimatedPlane,
                                         alignment: .horizontal)
            guard let first = results.first else { return }

            let transform = first.worldTransform
            Task { @MainActor in
                sessionModel.setAnchor(transform)
            }

            createOrUpdateAnchor(transform)
            // Overlay will update on the next SwiftUI update; this makes it feel immediate.
            applyOverlay(for: lastStepID ?? "")
        }

        func restoreAnchorIfNeeded() {
            guard let t = sessionModel.wheelTransform else { return }
            createOrUpdateAnchor(t)
        }

        func clearAnchor() {
            guard let arView, let anchor = wheelAnchor else { return }
            if let idx = arView.scene.anchors.firstIndex(where: { $0 === anchor }) {
                arView.scene.anchors.remove(at: idx)
            }
            wheelAnchor = nil
        }

        private func createOrUpdateAnchor(_ transform: simd_float4x4) {
            guard let arView else { return }

            if wheelAnchor == nil {
                let anchor = AnchorEntity(world: transform)
                wheelAnchor = anchor
                arView.scene.addAnchor(anchor)
            } else {
                wheelAnchor?.transform.matrix = transform
            }
        }

        func applyOverlay(for stepID: String) {
            // Avoid rebuilding overlay constantly.
            if lastStepID == stepID { return }
            lastStepID = stepID

            guard sessionModel.hasAnchor else { return }
            guard let anchor = wheelAnchor else { return }

            // Rebuild overlay each step.
            anchor.children.removeAll()

            // Always show wheel ring
            let ring = ModelEntity(
                mesh: .generateCylinder(height: 0.01, radius: 0.15),
                materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
            )
            ring.position = [0, 0, 0]
            anchor.addChild(ring)

            switch overlayKind(for: stepID) {
            case .ringOnly:
                break
            case .lugs:
                addLugMarkers(to: anchor, color: .systemRed)
            case .studs:
                addLugMarkers(to: anchor, color: .systemGreen)
            case .starPattern:
                addLugMarkers(to: anchor, color: .systemBlue)
                animateStarPattern(to: anchor)
            }
        }

        private enum OverlayKind { case ringOnly, lugs, studs, starPattern }

        // Map your real step IDs here
        private func overlayKind(for stepID: String) -> OverlayKind {
            switch stepID {
            case "ft_loosen", "ft_remove":
                return .lugs
            case "ft_mount":
                return .studs
            case "ft_lower", "ft_aftercare":
                return .starPattern
            default:
                return .ringOnly
            }
        }

        private func lugPositions(radius: Float = 0.10, count: Int = 5) -> [SIMD3<Float>] {
            (0..<count).map { i in
                let angle = Float(i) * (2 * .pi / Float(count))
                return [radius * cos(angle), 0.01, radius * sin(angle)]
            }
        }

        private func addLugMarkers(to anchor: AnchorEntity, color: UIColor) {
            for p in lugPositions() {
                let lug = ModelEntity(
                    mesh: .generateSphere(radius: 0.015),
                    materials: [SimpleMaterial(color: color, isMetallic: false)]
                )
                lug.position = p
                anchor.addChild(lug)
            }
        }

        private func animateStarPattern(to anchor: AnchorEntity) {
            let positions = lugPositions()
            let pairs: [(Int, Int)] = [(0,2),(2,4),(4,1),(1,3),(3,0)]

            for (idx, pair) in pairs.enumerated() {
                let delay = Double(idx) * 0.18
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let a = positions[pair.0]
                    let b = positions[pair.1]
                    anchor.addChild(self.cylinderBetween(a, b, radius: 0.004, color: .systemBlue))
                }
            }
        }

        private func cylinderBetween(_ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: Float, color: UIColor) -> ModelEntity {
            let diff = b - a
            let height = max(simd_length(diff), 0.001)

            let entity = ModelEntity(
                mesh: MeshResource.generateCylinder(height: height, radius: radius),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            entity.position = (a + b) / 2

            let up = SIMD3<Float>(0, 1, 0)
            let dir = simd_normalize(diff)
            let axis = simd_cross(up, dir)

            if simd_length(axis) > 1e-5 {
                let angle = acos(clamp(simd_dot(up, dir), -1, 1))
                entity.orientation = simd_quatf(angle: angle, axis: simd_normalize(axis))
            }

            return entity
        }

        private func clamp(_ x: Float, _ a: Float, _ b: Float) -> Float { min(max(x, a), b) }
    }
}
