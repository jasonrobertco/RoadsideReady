import SwiftUI
import UIKit
import RealityKit
import ARKit
import Foundation
import simd

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
        arView.automaticallyConfigureSession = false
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
        private var lastTightenedKey: String = ""
        private var lastActiveKey: String = ""
        private var lastSetupConfirmed: Bool = false
        private var lastResetRequest: Int = 0
        private var awaitingReadyAfterReset: Bool = false
        private let repositionMaxMeters: Float = 0.75

        private var ringEntity: ModelEntity?
        private var lugEntities: [Int: ModelEntity] = [:]

        private let tightenSteps: Set<String> = ["ft_mount", "ft_lower", "ft_aftercare"]

        #if DEBUG
        private var planeAxisAnchors: [AnchorEntity] = []
        private var planeAxisIDs: Set<UUID> = []
        private let maxPlaneAxis: Int = 3
        private var axesArmed: Bool = true
        #endif

        // Cached meshes (avoid reallocation)
        private let ringMesh = MeshResource.generateCylinder(height: 0.006, radius: 0.22)

        private let lugHeadMesh: MeshResource
        private let lugStemMesh: MeshResource

        private let matBlue = SimpleMaterial(color: .systemBlue, isMetallic: false)
        private let matRed = SimpleMaterial(color: .systemRed, isMetallic: false)
        private let matGreen = SimpleMaterial(color: .systemGreen, isMetallic: false)

        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
            self.lugHeadMesh = Coordinator.makeHexPrismMesh(height: 0.010, radius: 0.015)
            self.lugStemMesh = MeshResource.generateCylinder(height: 0.014, radius: 0.007)
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

            let tightenedKey = sessionModel.tightenedLugs.sorted().map(String.init).joined(separator: ",")
            let activeKey = sessionModel.activeLugIndex.map(String.init) ?? "-"
            let setup = sessionModel.lugSetupConfirmed

            // If nothing relevant changed, do nothing (prevents CPU spikes)
            if stepID == lastStepID,
               lugCount == lastLugCount,
               sessionModel.isLocked == lastLocked,
               loosenedKey == lastLoosenedKey,
               tightenedKey == lastTightenedKey,
               activeKey == lastActiveKey,
               setup == lastSetupConfirmed {
                return
            }

            let enteringTighten = (stepID != lastStepID) && tightenSteps.contains(stepID) && !tightenSteps.contains(lastStepID)
            if enteringTighten, sessionModel.lugSetupConfirmed {
                self.sessionModel.beginTightenSequence()
            }

            lastStepID = stepID
            lastLugCount = lugCount
            lastLocked = sessionModel.isLocked
            lastLoosenedKey = loosenedKey
            lastTightenedKey = tightenedKey
            lastActiveKey = activeKey
            lastSetupConfirmed = setup

            renderReuse()
        }

        func syncFromModel(stepID: String, lugCount: Int) {
            update(stepID: stepID, lugCount: lugCount)
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = sender.location(in: arView)
            showTapFeedback(in: arView, at: location)

            // A) Lug taps (loosen or tighten steps, only when locked and after setup)
            if sessionModel.isLocked,
               sessionModel.lugSetupConfirmed,
               let entity = arView.entity(at: location),
               entity.name.hasPrefix("rr_lug_"),
               let idx = Int(entity.name.replacingOccurrences(of: "rr_lug_", with: "")) {

                if lastStepID == "ft_loosen" {
                    self.sessionModel.toggleLoosened(idx)
                } else if tightenSteps.contains(lastStepID) {
                    self.sessionModel.handleTightenTap(idx)
                }
                renderReuse()
                return
            }

            // B) If already locked, do not allow reposition
            if sessionModel.isLocked {
                Task { @MainActor in
                    self.sessionModel.setStatus("Locked. Use Redo to move.")
                }
                return
            }

            // C) Place/reposition with “best hit” selection (prevents snapping)
            guard let hit = bestRaycastHit(in: arView, at: location) else {
                Task { @MainActor in
                    self.sessionModel.setStatus("No surface found. Move device slowly, then tap.")
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
                self.sessionModel.setAnchor(transform)
                self.sessionModel.resetLugs()
                self.sessionModel.lock() // ALWAYS lock after first placement
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

            #if DEBUG
            for a in planeAxisAnchors { a.removeFromParent() }
            planeAxisAnchors.removeAll()
            planeAxisIDs.removeAll()
            axesArmed = false
            #endif

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
                    #if DEBUG
                    axesArmed = true
                    applyPlaneAxesFromCurrentFrame(session)
                    #endif

                    self.sessionModel.setStatus("Ready", phase: .ready)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self.sessionModel.setStatus(nil, phase: .none)
                    }
                }
            }
        }

        #if DEBUG
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard axesArmed else { return }
            Task { @MainActor in
                guard let arView else { return }
                guard planeAxisAnchors.count < maxPlaneAxis else { return }

                for case let plane as ARPlaneAnchor in anchors {
                    guard planeAxisAnchors.count < maxPlaneAxis else { break }
                    guard !planeAxisIDs.contains(plane.identifier) else { continue }

                    planeAxisIDs.insert(plane.identifier)
                    let a = AnchorEntity(anchor: plane)
                    a.name = "rr_plane_axis_\(plane.identifier)"
                    a.addChild(makeAxis())
                    arView.scene.addAnchor(a)
                    planeAxisAnchors.append(a)
                }
            }
        }
        #endif

        #if DEBUG
        private func applyPlaneAxesFromCurrentFrame(_ session: ARSession) {
            guard let arView else { return }
            guard planeAxisAnchors.count < maxPlaneAxis else { return }
            guard let frame = session.currentFrame else { return }

            for case let plane as ARPlaneAnchor in frame.anchors {
                guard planeAxisAnchors.count < maxPlaneAxis else { break }
                guard !planeAxisIDs.contains(plane.identifier) else { continue }

                planeAxisIDs.insert(plane.identifier)
                let a = AnchorEntity(anchor: plane)
                a.name = "rr_plane_axis_\(plane.identifier)"
                a.addChild(makeAxis())
                arView.scene.addAnchor(a)
                planeAxisAnchors.append(a)
            }
        }
        #endif

        #if DEBUG
        private func makeAxis() -> Entity {
            let root = Entity()
            let length: Float = 0.20
            let t: Float = 0.06 // thickness scale

            let x = ModelEntity(mesh: .generateBox(size: length), materials: [SimpleMaterial(color: .systemRed, isMetallic: false)])
            x.scale = [1, t, t]
            x.position.x = length / 2

            let y = ModelEntity(mesh: .generateBox(size: length), materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)])
            y.scale = [t, 1, t]
            y.position.y = length / 2

            let z = ModelEntity(mesh: .generateBox(size: length), materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            z.scale = [t, t, 1]
            z.position.z = length / 2

            root.addChild(x)
            root.addChild(y)
            root.addChild(z)
            return root
        }
        #endif

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

            return nil
        }

        // MARK: - Rendering

        private func renderReuse() {
            guard let anchor = wheelAnchor else { return }

            // Ensure ring exists once
            if ringEntity == nil {
                let color = UIColor.systemGray.withAlphaComponent(0.25)
                let ring = ModelEntity(mesh: ringMesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
                ring.name = "rr_ring"
                ring.position = [0, 0.012, 0]
                ringEntity = ring
                anchor.addChild(ring)
            }

            // Lugs visible after setup is confirmed AND locked
            let showLugs = (sessionModel.lugSetupConfirmed && sessionModel.isLocked)

            if !showLugs {
                // Hide (don’t remove) lug entities
                for (_, lug) in lugEntities { lug.isEnabled = false }
                return
            }

            // Ensure lug entities exist up to lugCount (create once)
            let positions = lugPositions(count: lastLugCount, radius: 0.13)
            for i in 0..<lastLugCount {
                if lugEntities[i] == nil {
                    let head = ModelEntity(mesh: lugHeadMesh, materials: [matBlue])
                    head.name = "rr_lug_\(i)"
                    head.components.set(InputTargetComponent())
                    head.generateCollisionShapes(recursive: false)   // collision on head only

                    let stem = ModelEntity(mesh: lugStemMesh, materials: [matBlue])
                    stem.name = "rr_lug_stem"
                    stem.position = [0, -0.010, 0] // place stem below the head
                    head.addChild(stem)

                    lugEntities[i] = head
                    anchor.addChild(head)
                }
            }

            // Update positions + colors + visibility (cheap)
            for i in 0..<lastLugCount {
                guard let lug = lugEntities[i] else { continue }
                lug.isEnabled = true
                if i < positions.count { lug.position = positions[i] }

                let mat: SimpleMaterial
                if lastStepID == "ft_loosen" {
                    mat = sessionModel.loosenedLugs.contains(i) ? matGreen : matBlue
                } else if tightenSteps.contains(lastStepID) {
                    if i == sessionModel.activeLugIndex { mat = matRed }
                    else if sessionModel.tightenedLugs.contains(i) { mat = matGreen }
                    else { mat = matBlue }
                } else {
                    mat = matBlue
                }

                lug.model?.materials = [mat]
                if let stem = lug.findEntity(named: "rr_lug_stem") as? ModelEntity {
                    stem.model?.materials = [mat]
                }
            }

            // Hide any extras from previous larger lugCount
            for (i, lug) in lugEntities where i >= lastLugCount {
                lug.isEnabled = false
            }
        }

        private func lugPositions(count: Int, radius: Float = 0.13) -> [SIMD3<Float>] {
            guard count > 0 else { return [] }
            return (0..<count).map { i in
                let angle = Float(i) * (2 * .pi / Float(count))
                // x/z lie in the surface plane; y is surface normal
                return [radius * cos(angle), 0.016, radius * sin(angle)]
            }
        }

        private static func makeHexPrismMesh(height: Float, radius: Float) -> MeshResource {
            var desc = MeshDescriptor()

            let h = height / 2
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []

            // 0..5 bottom ring, 6..11 top ring
            for i in 0..<6 {
                let a = Float(i) * (2 * .pi / 6)
                let x = radius * cos(a)
                let z = radius * sin(a)
                positions.append([x, -h, z])
                normals.append(simd_normalize([x, 0, z])) // outward
            }
            for i in 0..<6 {
                let a = Float(i) * (2 * .pi / 6)
                let x = radius * cos(a)
                let z = radius * sin(a)
                positions.append([x,  h, z])
                normals.append(simd_normalize([x, 0, z])) // outward
            }

            let bottomCenter: UInt32 = 12
            let topCenter: UInt32 = 13
            positions.append([0, -h, 0]); normals.append([0, -1, 0])
            positions.append([0,  h, 0]); normals.append([0,  1, 0])

            desc.positions = MeshBuffers.Positions(positions)
            desc.normals   = MeshBuffers.Normals(normals)

            var idx: [UInt32] = []

            // Sides (6 quads => 12 triangles)
            for i: UInt32 in 0..<6 {
                let b0 = i
                let b1 = (i + 1) % 6
                let t0 = i + 6
                let t1 = ((i + 1) % 6) + 6
                idx += [b0, t0, t1,  b0, t1, b1]
            }

            // Bottom cap (CCW when viewed from below)
            for i: UInt32 in 0..<6 {
                let b0 = i
                let b1 = (i + 1) % 6
                idx += [bottomCenter, b0, b1]
            }

            // Top cap (CCW when viewed from above)
            for i: UInt32 in 0..<6 {
                let t0 = i + 6
                let t1 = ((i + 1) % 6) + 6
                idx += [topCenter, t1, t0]
            }

            desc.primitives = .triangles(idx)

            do {
                return try MeshResource.generate(from: [desc])
            } catch {
                #if DEBUG
                print("Hex mesh gen failed:", error)
                #endif
                return .generateCylinder(height: height, radius: radius)
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

