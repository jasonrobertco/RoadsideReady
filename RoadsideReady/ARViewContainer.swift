import SwiftUI
import UIKit
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    let currentStepID: String
    let lugCount: Int
    @ObservedObject var sessionModel: ARSessionModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.isAutoFocusEnabled = true
        arView.session.run(config)

        #if DEBUG
        // arView.debugOptions.insert(.showFeaturePoints)
        // arView.debugOptions.insert(.showAnchorOrigins)
        #endif

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.attach(arView)
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionModel: sessionModel)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let sessionModel: ARSessionModel
        weak var arView: ARView?

        private var wheelAnchor: AnchorEntity?
        private var lastStepID: String = ""
        private var lastLugCount: Int = 5

        private var lastLocked: Bool = false
        private var lastLoosenedKey: String = ""
        private var lastResetRequest: Int = 0
        private var awaitingReadyAfterReset: Bool = false
        private let repositionMaxMeters: Float = 0.75

        private var ringEntity: ModelEntity?
        private var lugEntities: [Int: ModelEntity] = [:]

        // Cached meshes (avoid reallocation)
        private let ringMesh = MeshResource.generateCylinder(height: 0.006, radius: 0.22)
        private let lugMesh  = MeshResource.generateSphere(radius: 0.014)

        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
        }

        func attach(_ arView: ARView) {
            self.arView = arView
            arView.session.delegate = self
        }

        func update(stepID: String, lugCount: Int) {
            // Handle "Redo camera" requests
            if sessionModel.resetRequest != lastResetRequest {
                lastResetRequest = sessionModel.resetRequest
                resetARSession()
                return
            }

            // Only touch Published state if it actually changed
            if sessionModel.expectedLugCount != lugCount {
                Task { @MainActor in self.sessionModel.setExpectedLugCount(lugCount) }
            }

            // Build a stable key for loosened set to detect changes cheaply
            let loosenedKey = sessionModel.loosenedLugs.sorted().map(String.init).joined(separator: ",")

            // If nothing relevant changed, do nothing (prevents CPU spikes)
            if stepID == lastStepID,
               lugCount == lastLugCount,
               sessionModel.isLocked == lastLocked,
               loosenedKey == lastLoosenedKey {
                return
            }

            lastStepID = stepID
            lastLugCount = lugCount
            lastLocked = sessionModel.isLocked
            lastLoosenedKey = loosenedKey

            restoreAnchorIfNeeded()
            renderReuse()
        }

        func syncFromModel(stepID: String, lugCount: Int) {
            update(stepID: stepID, lugCount: lugCount)
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = sender.location(in: arView)
            showTapFeedback(in: arView, at: location)

            // A) Lug taps (only on loosen step AND locked)
            if lastStepID == "ft_loosen",
               sessionModel.isLocked,
               let entity = arView.entity(at: location),
               entity.name.hasPrefix("rr_lug_"),
               let idx = Int(entity.name.replacingOccurrences(of: "rr_lug_", with: "")) {
                Task { @MainActor in self.sessionModel.toggleLoosened(idx) }
                renderReuse()
                return
            }

            // B) If locked, don't allow reposition
            if sessionModel.isLocked {
                Task { @MainActor in
                    self.sessionModel.setStatus("Locked. Use Redo to move.")
                }
                return
            }

            // C) Place/reposition with “best hit” selection (prevents snapping)
            guard let hit = bestRaycastHit(in: arView, at: location) else {
                Task { @MainActor in
                    self.sessionModel.setStatus("No surface found. Move iPad slowly, then tap.")
                }
                return
            }

            // If already placed, only allow reposition if tap hit is near current anchor
            if let current = sessionModel.wheelTransform {
                let currentPos = SIMD3<Float>(current.columns.3.x, current.columns.3.y, current.columns.3.z)
                let newPos = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
                let dist = simd_length(newPos - currentPos)
                if dist > repositionMaxMeters {
                    Task { @MainActor in
                        self.sessionModel.setStatus("Tap near the ring to adjust (or press Redo).")
                    }
                    return
                }
            }

            let transform = hit.worldTransform
            Task { @MainActor in
                self.sessionModel.setAnchor(transform)   // sets isLocked=false
                self.sessionModel.resetLugs()
            }

            createOrUpdateAnchor(transform)
            renderReuse()

            Task { @MainActor in
                self.sessionModel.setStatus("Placed ✓")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.sessionModel.setStatus(nil, phase: .none)
                }
            }
        }

        private func restoreAnchorIfNeeded() {
            Task { @MainActor in
                guard let t = self.sessionModel.wheelTransform else { return }
                self.createOrUpdateAnchor(t)
            }
        }

        private func createOrUpdateAnchor(_ transform: simd_float4x4) {
            guard let arView else { return }
            if wheelAnchor == nil {
                let a = AnchorEntity(world: transform)
                wheelAnchor = a
                arView.scene.addAnchor(a)
            } else {
                wheelAnchor?.transform.matrix = transform
            }
        }

        private func resetARSession() {
            guard let arView else { return }

            // Clear scene + cached entities
            wheelAnchor?.removeFromParent()
            wheelAnchor = nil
            ringEntity = nil
            lugEntities.removeAll()

            Task { @MainActor in
                self.sessionModel.resetAlignment()
                self.sessionModel.setStatus("Resetting AR…", phase: .resetting)
            }

            awaitingReadyAfterReset = true

            if let config = arView.session.configuration {
                arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            }
        }

        // ARSessionDelegate: when tracking becomes normal after reset -> show checkmark
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            guard awaitingReadyAfterReset else { return }

            if case .normal = camera.trackingState {
                awaitingReadyAfterReset = false

                Task { @MainActor in
                    self.sessionModel.setStatus("Ready", phase: .ready)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.sessionModel.setStatus(nil, phase: .none)
                    }
                }
            }
        }

        private func distanceFromCamera(to worldTransform: simd_float4x4, in arView: ARView) -> Float {
            let cameraPos = arView.cameraTransform.translation
            let hitPos = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            return simd_length(hitPos - cameraPos)
        }

        private func bestRaycastHit(in arView: ARView, at location: CGPoint) -> ARRaycastResult? {
            // Prefer stable plane results first (prevents “snap”)
            let preferred: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment, Float)] = [
                (.existingPlaneGeometry, .any, 3.0),
                (.existingPlaneInfinite, .any, 3.0)
            ]

            for (target, alignment, maxDist) in preferred {
                if let q = arView.makeRaycastQuery(from: location, allowing: target, alignment: alignment) {
                    let results = arView.session.raycast(q)
                    if let first = results.first {
                        let d = distanceFromCamera(to: first.worldTransform, in: arView)
                        if d < maxDist { return first }
                    }
                }
            }

            // Fallback: estimated plane, but only if close (this is what causes weird jumps if unbounded)
            if let q = arView.makeRaycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
                let results = arView.session.raycast(q)
                if let first = results.first {
                    let d = distanceFromCamera(to: first.worldTransform, in: arView)
                    if d < 1.2 { return first }
                }
            }

            return nil
        }

        // MARK: - Rendering

        private func renderReuse() {
            guard let anchor = wheelAnchor else { return }

            // Ensure ring exists once
            if ringEntity == nil {
                let color = UIColor.systemBlue.withAlphaComponent(0.30)
                let ring = ModelEntity(mesh: ringMesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
                ring.name = "rr_ring"
                ring.position = [0, 0.012, 0]
                ringEntity = ring
                anchor.addChild(ring)
            }

            // Lugs only visible on ft_loosen AND locked
            let showLugs = (lastStepID == "ft_loosen" && sessionModel.isLocked)

            if !showLugs {
                // Hide (don’t remove) lug entities
                for (_, lug) in lugEntities { lug.isEnabled = false }
                return
            }

            // Ensure lug entities exist up to lugCount (create once)
            let positions = lugPositions(count: lastLugCount, radius: 0.13)
            for i in 0..<lastLugCount {
                if lugEntities[i] == nil {
                    let lug = ModelEntity(mesh: lugMesh, materials: [SimpleMaterial(color: .systemOrange, isMetallic: false)])
                    lug.name = "rr_lug_\(i)"
                    lug.components.set(InputTargetComponent())
                    lug.generateCollisionShapes(recursive: true)   // do this ONCE
                    lugEntities[i] = lug
                    anchor.addChild(lug)
                }
            }

            // Update positions + colors + visibility (cheap)
            for i in 0..<lastLugCount {
                guard let lug = lugEntities[i] else { continue }
                lug.isEnabled = true
                if i < positions.count { lug.position = positions[i] }

                let isOn = sessionModel.loosenedLugs.contains(i)
                lug.model?.materials = [SimpleMaterial(color: isOn ? .systemGreen : .systemOrange, isMetallic: false)]
            }

            // Hide any extras from previous larger lugCount
            for (i, lug) in lugEntities where i >= lastLugCount {
                lug.isEnabled = false
            }
        }

        private func addWheelDisk(to anchor: AnchorEntity) {
            // This faces “out of” the detected surface because ARKit uses the surface normal as local +Y.
            let color = UIColor.systemBlue.withAlphaComponent(0.35)
            let disk = ModelEntity(
                mesh: .generateCylinder(height: 0.006, radius: 0.22),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            disk.name = "rr_ring"
            disk.position = [0, 0.012, 0] // 1.2 cm off surface to avoid z-fighting
            anchor.addChild(disk)
        }

        private func lugPositions(count: Int, radius: Float = 0.13) -> [SIMD3<Float>] {
            guard count > 0 else { return [] }
            return (0..<count).map { i in
                let angle = Float(i) * (2 * .pi / Float(count))
                // x/z lie in the surface plane; y is surface normal
                return [radius * cos(angle), 0.016, radius * sin(angle)]
            }
        }

        private func addLugMarkers(to anchor: AnchorEntity, count: Int) {
            let positions = lugPositions(count: count)

            for (i, p) in positions.enumerated() {
                let isOn = sessionModel.loosenedLugs.contains(i)
                let lug = ModelEntity(
                    mesh: .generateSphere(radius: 0.014),
                    materials: [SimpleMaterial(color: isOn ? .systemGreen : .systemOrange, isMetallic: false)]
                )
                lug.name = "rr_lug_\(i)"
                lug.position = p

                lug.components.set(InputTargetComponent())
                lug.generateCollisionShapes(recursive: true)

                anchor.addChild(lug)
            }
        }

        // MARK: - Tap feedback

        private func showTapFeedback(in arView: ARView, at point: CGPoint) {
            let size: CGFloat = 12
            let dot = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
            dot.backgroundColor = UIColor.systemBlue
            dot.layer.cornerRadius = size / 2
            dot.alpha = 0.9
            dot.isUserInteractionEnabled = false
            dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)

            arView.addSubview(dot)

            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
                dot.transform = .identity
            }
            UIView.animate(withDuration: 0.35, delay: 0.12, options: [.curveEaseIn]) {
                dot.alpha = 0
                dot.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
            } completion: { _ in
                dot.removeFromSuperview()
            }
        }
    }
}

