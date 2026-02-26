import SwiftUI
import UIKit
import RealityKit
import ARKit
import simd

struct ARViewContainer: UIViewRepresentable {
    let currentStepID: String
    let lugCount: Int
    @ObservedObject var sessionModel: ARSessionModel
    let isActive: Bool

    init(currentStepID: String, lugCount: Int, sessionModel: ARSessionModel, isActive: Bool = true) {
        self.currentStepID = currentStepID
        self.lugCount = lugCount
        self.sessionModel = sessionModel
        self.isActive = isActive
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.isAutoFocusEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.attach(arView, config: config)
        context.coordinator.setActive(isActive)
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.setActive(isActive)
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionModel: sessionModel) }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let sessionModel: ARSessionModel
        weak var arView: ARView?

        private var config: ARWorldTrackingConfiguration?
        private var sessionRunning: Bool = false

        // Stable AR anchor
        private var wheelARAnchor: ARAnchor?
        private var anchorEntity: AnchorEntity?

        // Root under anchor (stays on ground)
        private var contentRoot: Entity?
        // Wheel content (moves up when jacked)
        private var wheelGroup: Entity?

        // Entities
        private var oldRing: ModelEntity?
        private var newRing: ModelEntity?
        private var jackBase: ModelEntity?
        private var jackLift: ModelEntity?
        private var jackTop: ModelEntity?

        private var lugEntities: [Int: ModelEntity] = [:]      // head; stem is child
        private var lugArrowEntities: [Int: Entity] = [:]      // per-lug arrow group

        // Lug state (kept local so reverse is deterministic)
        private var removedLugs: Set<Int> = []

        // Stage machine (drives reverse animation)
        private enum Stage: Equatable {
            case base
            case loosen
            case jackPlaced
            case jackUp
            case removed
            case mount
            case lowered
        }

        private var stage: Stage = .base
        private var lastStepID: String = ""
        private var lastResetRequest: Int = 0
        private var transitionTask: Task<Void, Never>?

        // ---- Geometry tuning (local to anchor plane) ----
        // Ring annulus
        private let ringOuterR: Float = 0.22
        private let ringInnerR: Float = 0.16
        private let ringHeight: Float = 0.006

        // Lug pattern radius: inside inner radius
        private let lugPatternRadius: Float = 0.11

        // Lift above surface to avoid flicker
        private let ringY: Float = 0.030
        private let lugBaseY: Float = 0.042

        // Jack + wheel lift (normal is +Y in local frame)
        private let jackLiftY: Float = 0.08

        // Loosen: slight radial out + slight turn
        private let lugLooseRadialOut: Float = 0.015
        private let lugLooseRotation: Float = .pi / 10   // ~18°

        // Remove: out along normal
        private let lugRemovedNormalOut: Float = 0.12

        // Arrow travel: ~1 ft = 0.30m
        private let arrowTravel: Float = 0.30

        // ---- Cached meshes/materials (low power) ----
        private lazy var ringMesh: MeshResource =
            Self.makeAnnulusMesh(height: ringHeight, inner: ringInnerR, outer: ringOuterR, segments: 48)

        private let headHeight: Float = 0.010
        private let headRadius: Float = 0.015
        private let stemHeight: Float = 0.030   // 3× head height
        private let stemRadius: Float = 0.0065

        private lazy var lugHeadMesh = Self.makeHexPrismMesh(height: headHeight, radius: headRadius)
        private lazy var lugStemMesh = MeshResource.generateCylinder(height: stemHeight, radius: stemRadius)

        private let arrowStemMesh = MeshResource.generateCylinder(height: 0.10, radius: 0.008)
        private let arrowHeadMesh = MeshResource.generateCone(height: 0.05, radius: 0.02)

        private let jackBaseMesh = MeshResource.generateBox(size: [0.10, 0.02, 0.10])
        private let jackLiftMesh = MeshResource.generateBox(size: [0.04, 0.06, 0.04])
        private let jackTopMesh  = MeshResource.generateBox(size: [0.06, 0.02, 0.06])

        private let matRingGray = SimpleMaterial(color: UIColor.systemGray.withAlphaComponent(0.50), isMetallic: false)
        private let matRingBlue = SimpleMaterial(color: UIColor.systemBlue.withAlphaComponent(0.50), isMetallic: false)

        private let matBlue   = SimpleMaterial(color: .systemBlue, isMetallic: false)
        private let matOrange = SimpleMaterial(color: .systemOrange, isMetallic: false)
        private let matRed    = SimpleMaterial(color: .systemRed, isMetallic: false)
        private let matJack   = SimpleMaterial(color: UIColor(white: 0.15, alpha: 0.9), isMetallic: false)

        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
        }

        func attach(_ arView: ARView, config: ARWorldTrackingConfiguration) {
            self.arView = arView
            self.config = config
            arView.session.delegate = self
        }

        func setActive(_ active: Bool) {
            guard let arView, let config else { return }
            guard active != sessionRunning else { return }
            sessionRunning = active
            if active { arView.session.run(config) }
            else { arView.session.pause() }
        }

        // MARK: - Update

        func update(stepID: String, lugCount: Int) {
            if sessionModel.resetRequest != lastResetRequest {
                lastResetRequest = sessionModel.resetRequest
                resetARSession()
                return
            }

            if sessionModel.expectedLugCount != lugCount {
                sessionModel.setExpectedLugCount(lugCount)
            }

            syncAnchorFromModelIfNeeded()

            if stepID != lastStepID {
                lastStepID = stepID
                transition(to: stageForStep(stepID))
            }

            ensureStaticExists()
            applyStageSnapshot(animated: false) // keep visuals consistent
        }

        // MARK: - Tap placement

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = sender.location(in: arView)
            showTapFeedback(in: arView, at: location)

            if sessionModel.isLocked {
                sessionModel.setStatus("Locked. Use Redo to move.")
                return
            }

            guard let hit = bestRaycastHit(in: arView, at: location) else {
                sessionModel.setStatus("No surface found. Move device slowly, then tap.")
                return
            }

            placeAnchor(from: hit)

            sessionModel.setStatus("Placed ✓")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.sessionModel.setStatus(nil, phase: .none)
            }
        }

        // MARK: - Stage mapping

        private func stageForStep(_ stepID: String) -> Stage {
            switch stepID {
            case "ft_loosen":
                return .loosen
            case "ft_jackpoint":
                return .jackPlaced
            case "ft_jackup":
                return .jackUp
            case "ft_remove":
                return .removed
            case "ft_mount":
                return .mount
            case "ft_lower", "ft_aftercare":
                return .lowered
            default:
                return .base
            }
        }

        // MARK: - Transition (reversible)

        private func transition(to target: Stage, immediate: Bool = false) {
            guard contentRoot != nil else { stage = target; return }

            transitionTask?.cancel()
            transitionTask = nil

            let from = stage
            stage = target

            if immediate {
                applyStageSnapshot(animated: false)
                return
            }

            transitionTask = Task { @MainActor in
                await animateTransition(from: from, to: target)
            }
        }

        private func animateTransition(from: Stage, to: Stage) async {
            // Wheel lift + jack lift + ring swap
            applyStageSnapshot(animated: true)

            // Sequential lug motion only for these stages
            if to == .loosen || from == .loosen {
                await animateLugsSequentialForCurrentStage()
            }
            if to == .removed || from == .removed {
                await animateLugsSequentialForCurrentStage()
            }

            // Tire swap is special (mount ↔ removed)
            if from != .mount && to == .mount {
                await animateTireSwapForward()
            } else if from == .mount && to != .mount {
                await animateTireSwapReverse()
            }
        }

        // MARK: - Apply snapshot

        private func applyStageSnapshot(animated: Bool) {
            guard let contentRoot, let wheelGroup else { return }

            // 1) Jack visibility + lift
            let jackVisible: Bool = (stage == .jackPlaced || stage == .jackUp || stage == .removed || stage == .mount)
            let jackExtended: Bool = (stage == .jackUp || stage == .removed || stage == .mount)

            setJack(visible: jackVisible, extended: jackExtended, animated: animated)

            // 2) Wheel lift (only wheelGroup moves)
            let wheelLift: Float = (stage == .jackUp || stage == .removed || stage == .mount) ? jackLiftY : 0
            setWheelLift(wheelLift, animated: animated)

            // 3) Ring color/state (mount/lowered => blue ring)
            ensureRingsExist()
            let showBlue = (stage == .mount || stage == .lowered)
            setRingState(showBlue: showBlue)

            // 4) Lug targets + arrows (removed => arrows)
            ensureLugsExist()
            ensureLugArrowsExist()

            let showArrows = (stage == .removed)
            setArrows(visible: showArrows, animated: animated)

            // Lugs:
            // loosen: orange + slight rotate + slight radial out
            // removed: red + up along normal + arrows
            // mount/lowered/base: blue + seated
            if animated {
                // leave positioning to animation functions below for sequential clarity
            } else {
                snapLugsToCurrentStage()
            }
        }

        // MARK: - Lugs

        private func snapLugsToCurrentStage() {
            let n = sessionModel.expectedLugCount
            let base = lugPositions(count: n, radius: lugPatternRadius)

            for i in 0..<n {
                guard let lug = lugEntities[i], i < base.count else { continue }

                let p = base[i]
                let radial = simd_normalize(SIMD3<Float>(p.x, 0, p.z))

                switch stage {
                case .loosen, .jackPlaced, .jackUp:
                    let pos = SIMD3<Float>(p.x + radial.x * lugLooseRadialOut,
                                           lugBaseY,
                                           p.z + radial.z * lugLooseRadialOut)
                    let q = simd_quatf(angle: lugLooseRotation, axis: [0, 1, 0])
                    lug.transform = Transform(scale: .one, rotation: q, translation: pos)
                    setLugMaterial(lug, matOrange)

                case .removed:
                    let pos = SIMD3<Float>(p.x,
                                           lugBaseY + lugRemovedNormalOut,
                                           p.z)
                    let q = simd_quatf(angle: lugLooseRotation, axis: [0, 1, 0])
                    lug.transform = Transform(scale: .one, rotation: q, translation: pos)
                    setLugMaterial(lug, matRed)

                case .mount, .lowered, .base:
                    let pos = SIMD3<Float>(p.x, lugBaseY, p.z)
                    let q = simd_quatf(angle: 0, axis: [0, 1, 0])
                    lug.transform = Transform(scale: .one, rotation: q, translation: pos)
                    setLugMaterial(lug, matBlue)
                }
            }
        }

        private func animateLugsSequentialForCurrentStage() async {
            let n = sessionModel.expectedLugCount
            let base = lugPositions(count: n, radius: lugPatternRadius)

            for i in 0..<n {
                if Task.isCancelled { return }
                guard let lug = lugEntities[i], i < base.count else { continue }

                let p = base[i]
                let radial = simd_normalize(SIMD3<Float>(p.x, 0, p.z))

                let (pos, q, mat): (SIMD3<Float>, simd_quatf, SimpleMaterial) = {
                    switch stage {
                    case .loosen, .jackPlaced, .jackUp:
                        let pos = SIMD3<Float>(p.x + radial.x * lugLooseRadialOut,
                                               lugBaseY,
                                               p.z + radial.z * lugLooseRadialOut)
                        return (pos, simd_quatf(angle: lugLooseRotation, axis: [0, 1, 0]), matOrange)
                    case .removed:
                        let pos = SIMD3<Float>(p.x, lugBaseY + lugRemovedNormalOut, p.z)
                        return (pos, simd_quatf(angle: lugLooseRotation, axis: [0, 1, 0]), matRed)
                    case .mount, .lowered, .base:
                        let pos = SIMD3<Float>(p.x, lugBaseY, p.z)
                        return (pos, simd_quatf(angle: 0, axis: [0, 1, 0]), matBlue)
                    }
                }()

                lug.move(to: Transform(scale: .one, rotation: q, translation: pos),
                         relativeTo: wheelGroup,
                         duration: 0.30,
                         timingFunction: .easeInOut)

                setLugMaterial(lug, mat)
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }

        // MARK: - Arrows

        private func setArrows(visible: Bool, animated: Bool) {
            let n = sessionModel.expectedLugCount
            let base = lugPositions(count: n, radius: lugPatternRadius)

            for i in 0..<n {
                guard let arrow = lugArrowEntities[i], i < base.count else { continue }
                arrow.isEnabled = visible

                let p = base[i]
                let start = SIMD3<Float>(p.x, lugBaseY + 0.03, p.z)
                let end   = SIMD3<Float>(p.x, lugBaseY + arrowTravel, p.z)

                if animated {
                    arrow.move(to: Transform(translation: visible ? end : start),
                               relativeTo: wheelGroup,
                               duration: 0.45,
                               timingFunction: .easeInOut)
                } else {
                    arrow.transform.translation = visible ? end : start
                }
            }
        }

        // MARK: - Jack

        private func setJack(visible: Bool, extended: Bool, animated: Bool) {
            ensureJackExists()

            jackBase?.isEnabled = visible
            jackLift?.isEnabled = visible
            jackTop?.isEnabled = visible

            let liftY: Float = extended ? 0.06 : 0.02

            if animated {
                jackLift?.move(to: Transform(translation: [0, liftY, 0]),
                               relativeTo: contentRoot,
                               duration: 0.50,
                               timingFunction: .easeInOut)

                jackTop?.move(to: Transform(translation: [0, liftY + 0.05, 0]),
                              relativeTo: contentRoot,
                              duration: 0.50,
                              timingFunction: .easeInOut)
            } else {
                jackLift?.transform.translation = [0, liftY, 0]
                jackTop?.transform.translation  = [0, liftY + 0.05, 0]
            }
        }

        private func setWheelLift(_ y: Float, animated: Bool) {
            guard let wheelGroup else { return }
            if animated {
                wheelGroup.move(to: Transform(translation: [0, y, 0]),
                                relativeTo: contentRoot,
                                duration: 0.60,
                                timingFunction: .easeInOut)
            } else {
                wheelGroup.transform.translation = [0, y, 0]
            }
        }

        // MARK: - Tire swap

        private func animateTireSwapForward() async {
            ensureRingsExist()

            // old gray flies up/out and disappears
            if let oldRing {
                oldRing.isEnabled = true
                oldRing.move(to: Transform(translation: [0, ringY + 0.30, 0.18]),
                             relativeTo: wheelGroup,
                             duration: 0.55,
                             timingFunction: .easeInOut)
                try? await Task.sleep(nanoseconds: 550_000_000)
                oldRing.isEnabled = false
            }

            // new blue flies in along normal to original position
            if let newRing {
                newRing.isEnabled = true
                newRing.transform.translation = [0, ringY + 0.35, 0]
                newRing.move(to: Transform(translation: [0, ringY, 0]),
                             relativeTo: wheelGroup,
                             duration: 0.55,
                             timingFunction: .easeInOut)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            // nuts go in and turn blue
            await animateLugsSequentialForCurrentStage()
        }

        private func animateTireSwapReverse() async {
            ensureRingsExist()

            // new blue flies out (up), hide
            if let newRing {
                newRing.isEnabled = true
                newRing.move(to: Transform(translation: [0, ringY + 0.35, 0]),
                             relativeTo: wheelGroup,
                             duration: 0.45,
                             timingFunction: .easeInOut)
                try? await Task.sleep(nanoseconds: 450_000_000)
                newRing.isEnabled = false
            }

            // old gray returns
            if let oldRing {
                oldRing.isEnabled = true
                oldRing.transform.translation = [0, ringY + 0.30, 0.18]
                oldRing.move(to: Transform(translation: [0, ringY, 0]),
                             relativeTo: wheelGroup,
                             duration: 0.45,
                             timingFunction: .easeInOut)
            }

            // restore lugs based on current stage (likely removed)
            await animateLugsSequentialForCurrentStage()
        }

        private func setRingState(showBlue: Bool) {
            ensureRingsExist()
            if showBlue {
                oldRing?.model?.materials = [matRingGray]
                newRing?.model?.materials = [matRingBlue]
            } else {
                oldRing?.model?.materials = [matRingGray]
                newRing?.model?.materials = [matRingBlue]
            }
            // base behavior: gray visible; mount/lowered: blue visible
            oldRing?.isEnabled = !showBlue
            newRing?.isEnabled = showBlue
        }

        // MARK: - Creation

        private func ensureStaticExists() {
            guard wheelGroup != nil else { return }
            ensureRingsExist()
            ensureJackExists()
            ensureLugsExist()
            ensureLugArrowsExist()
        }

        private func ensureRingsExist() {
            guard let wheelGroup else { return }

            if oldRing == nil {
                let r = ModelEntity(mesh: ringMesh, materials: [matRingGray])
                r.name = "rr_old_ring"
                r.position = [0, ringY, 0]
                oldRing = r
                wheelGroup.addChild(r)
            }
            if newRing == nil {
                let r = ModelEntity(mesh: ringMesh, materials: [matRingBlue])
                r.name = "rr_new_ring"
                r.position = [0, ringY, 0]
                r.isEnabled = false
                newRing = r
                wheelGroup.addChild(r)
            }
        }

        private func ensureJackExists() {
            guard let root = contentRoot else { return }
            if jackBase == nil {
                let b = ModelEntity(mesh: jackBaseMesh, materials: [matJack])
                b.name = "rr_jack_base"
                b.position = [0, 0.01, 0]
                b.isEnabled = false
                jackBase = b
                root.addChild(b)
            }
            if jackLift == nil {
                let l = ModelEntity(mesh: jackLiftMesh, materials: [matJack])
                l.name = "rr_jack_lift"
                l.position = [0, 0.02, 0]
                l.isEnabled = false
                jackLift = l
                root.addChild(l)
            }
            if jackTop == nil {
                let t = ModelEntity(mesh: jackTopMesh, materials: [matJack])
                t.name = "rr_jack_top"
                t.position = [0, 0.07, 0]
                t.isEnabled = false
                jackTop = t
                root.addChild(t)
            }
        }

        private func ensureLugsExist() {
            guard let wheelGroup else { return }
            guard sessionModel.lugSetupConfirmed, sessionModel.isLocked else { return }

            let n = sessionModel.expectedLugCount
            for i in 0..<n {
                if lugEntities[i] == nil {
                    let head = ModelEntity(mesh: lugHeadMesh, materials: [matBlue])
                    head.name = "rr_lug_\(i)"
                    head.components.set(InputTargetComponent())
                    head.generateCollisionShapes(recursive: true)

                    let stem = ModelEntity(mesh: lugStemMesh, materials: [matBlue])
                    stem.name = "rr_lug_stem"
                    let stemY = -(headHeight * 0.5 + stemHeight * 0.5)
                    stem.position = [0, stemY, 0]
                    head.addChild(stem)

                    lugEntities[i] = head
                    wheelGroup.addChild(head)
                }
            }
        }

        private func ensureLugArrowsExist() {
            guard let wheelGroup else { return }
            let n = sessionModel.expectedLugCount
            for i in 0..<n {
                if lugArrowEntities[i] == nil {
                    let root = Entity()
                    root.name = "rr_lug_arrow_\(i)"
                    root.isEnabled = false

                    let stem = ModelEntity(mesh: arrowStemMesh, materials: [matRed])
                    let head = ModelEntity(mesh: arrowHeadMesh, materials: [matRed])
                    head.position = [0, 0.075, 0]
                    stem.addChild(head)

                    root.addChild(stem)
                    lugArrowEntities[i] = root
                    wheelGroup.addChild(root)
                }
            }
        }

        private func setLugMaterial(_ head: ModelEntity, _ mat: SimpleMaterial) {
            head.model?.materials = [mat]
            if let stem = head.findEntity(named: "rr_lug_stem") as? ModelEntity {
                stem.model?.materials = [mat]
            }
        }

        private func lugPositions(count: Int, radius: Float) -> [SIMD3<Float>] {
            guard count > 0 else { return [] }
            return (0..<count).map { i in
                let a = Float(i) * (2 * .pi / Float(count))
                return [radius * cos(a), lugBaseY, radius * sin(a)]
            }
        }

        // MARK: - Stable anchor placement

        private func placeAnchor(at transform: simd_float4x4) {
            guard let arView else { return }

            if let old = wheelARAnchor {
                arView.session.remove(anchor: old)
            }
            anchorEntity?.removeFromParent()

            let arAnchor = ARAnchor(transform: transform)
            wheelARAnchor = arAnchor
            arView.session.add(anchor: arAnchor)

            let ae = AnchorEntity(anchor: arAnchor)
            anchorEntity = ae
            arView.scene.addAnchor(ae)

            let root = Entity()
            root.name = "rr_content_root"
            contentRoot = root
            ae.addChild(root)

            let wg = Entity()
            wg.name = "rr_wheel_group"
            wheelGroup = wg
            root.addChild(wg)

            oldRing = nil
            newRing = nil
            jackBase = nil
            jackLift = nil
            jackTop = nil
            lugEntities.removeAll()
            lugArrowEntities.removeAll()
        }

        private func syncAnchorFromModelIfNeeded() {
            guard anchorEntity == nil, let t = sessionModel.wheelTransform else { return }
            placeAnchor(at: t)
        }

        // MARK: - Reset

        private func resetARSession() {
            guard let arView, let config else { return }

            transitionTask?.cancel()
            transitionTask = nil

            if let old = wheelARAnchor {
                arView.session.remove(anchor: old)
            }
            wheelARAnchor = nil

            anchorEntity?.removeFromParent()
            anchorEntity = nil
            contentRoot = nil
            wheelGroup = nil

            oldRing = nil
            newRing = nil
            jackBase = nil
            jackLift = nil
            jackTop = nil
            lugEntities.removeAll()
            lugArrowEntities.removeAll()
            removedLugs.removeAll()

            stage = .base
            lastStepID = ""

            sessionModel.resetAlignment()
            sessionModel.setStatus("Resetting AR…", phase: .resetting)
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        // MARK: - Raycast

        private func distanceFromCamera(to worldTransform: simd_float4x4, in arView: ARView) -> Float {
            let cameraPos = arView.cameraTransform.translation
            let hitPos = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            return simd_length(hitPos - cameraPos)
        }

        private func bestRaycastHit(in arView: ARView, at location: CGPoint) -> ARRaycastResult? {
            // Prefer real planes
            let preferred: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment, Float)] = [
                (.existingPlaneGeometry, .any, 3.0),
                (.existingPlaneInfinite, .any, 3.0)
            ]

            for (target, alignment, maxDist) in preferred {
                if let q = arView.makeRaycastQuery(from: location, allowing: target, alignment: alignment) {
                    let results = arView.session.raycast(q)
                    if let first = results.first, distanceFromCamera(to: first.worldTransform, in: arView) < maxDist {
                        return first
                    }
                }
            }

            // Bounded fallback for responsiveness
            if let q = arView.makeRaycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
                let results = arView.session.raycast(q)
                if let first = results.first, distanceFromCamera(to: first.worldTransform, in: arView) < 1.2 {
                    return first
                }
            }

            return nil
        }

        // MARK: - Mesh generators

        private static func makeHexPrismMesh(height: Float, radius: Float) -> MeshResource {
            var desc = MeshDescriptor()
            let h = height / 2
            var positions: [SIMD3<Float>] = []

            // bottom 0..5, top 6..11
            for i in 0..<6 {
                let a = Float(i) * (2 * .pi / 6)
                positions.append([radius * cos(a), -h, radius * sin(a)])
            }
            for i in 0..<6 {
                let a = Float(i) * (2 * .pi / 6)
                positions.append([radius * cos(a),  h, radius * sin(a)])
            }

            let bottomCenter: UInt32 = 12
            let topCenter: UInt32 = 13
            positions.append([0, -h, 0])
            positions.append([0,  h, 0])

            desc.positions = MeshBuffers.Positions(positions)

            var idx: [UInt32] = []

            // sides
            for i: UInt32 in 0..<6 {
                let b0 = i
                let b1 = (i + 1) % 6
                let t0 = i + 6
                let t1 = ((i + 1) % 6) + 6
                idx += [b0, t0, t1,  b0, t1, b1]
            }

            // bottom cap
            for i: UInt32 in 0..<6 {
                let b0 = i
                let b1 = (i + 1) % 6
                idx += [bottomCenter, b1, b0]
            }

            // top cap
            for i: UInt32 in 0..<6 {
                let t0 = i + 6
                let t1 = ((i + 1) % 6) + 6
                idx += [topCenter, t0, t1]
            }

            desc.primitives = .triangles(idx)

            do { return try MeshResource.generate(from: [desc]) }
            catch { return .generateCylinder(height: height, radius: radius) }
        }

        private static func makeAnnulusMesh(height: Float, inner: Float, outer: Float, segments: Int) -> MeshResource {
            var desc = MeshDescriptor()
            let h = height / 2
            let seg = max(12, segments)

            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(seg * 4)

            func addRing(y: Float, r: Float) {
                for i in 0..<seg {
                    let a = (Float(i) / Float(seg)) * (2 * .pi)
                    positions.append([r * cos(a), y, r * sin(a)])
                }
            }

            addRing(y: +h, r: outer) // top outer
            addRing(y: +h, r: inner) // top inner
            addRing(y: -h, r: outer) // bottom outer
            addRing(y: -h, r: inner) // bottom inner

            desc.positions = MeshBuffers.Positions(positions)

            var idx: [UInt32] = []
            let topOuterBase: UInt32 = 0
            let topInnerBase: UInt32 = UInt32(seg)
            let botOuterBase: UInt32 = UInt32(seg * 2)
            let botInnerBase: UInt32 = UInt32(seg * 3)

            for i in 0..<seg {
                let i0 = UInt32(i)
                let i1 = UInt32((i + 1) % seg)

                // Top face
                idx += [
                    topOuterBase + i0, topInnerBase + i0, topInnerBase + i1,
                    topOuterBase + i0, topInnerBase + i1, topOuterBase + i1
                ]
                // Bottom face (reverse)
                idx += [
                    botOuterBase + i0, botInnerBase + i1, botInnerBase + i0,
                    botOuterBase + i0, botOuterBase + i1, botInnerBase + i1
                ]
                // Outer wall
                idx += [
                    topOuterBase + i0, botOuterBase + i0, botOuterBase + i1,
                    topOuterBase + i0, botOuterBase + i1, topOuterBase + i1
                ]
                // Inner wall (reverse)
                idx += [
                    topInnerBase + i0, botInnerBase + i1, botInnerBase + i0,
                    topInnerBase + i0, topInnerBase + i1, botInnerBase + i1
                ]
            }

            desc.primitives = .triangles(idx)

            do { return try MeshResource.generate(from: [desc]) }
            catch { return .generateCylinder(height: height, radius: outer) }
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

            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) { dot.transform = .identity }
            UIView.animate(withDuration: 0.35, delay: 0.12, options: [.curveEaseIn]) {
                dot.alpha = 0
                dot.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
            } completion: { _ in
                dot.removeFromSuperview()
            }
        }

        // MARK: - New placeAnchor(from:) method

        private func placeAnchor(from hit: ARRaycastResult) {
            guard let arView else { return }

            // Build a transform whose local +Y is the surface normal (works for floor + wall)
            let t = orientedTransform(from: hit.worldTransform)

            if let old = wheelARAnchor {
                arView.session.remove(anchor: old)
            }
            anchorEntity?.removeFromParent()

            let arAnchor = ARAnchor(transform: t)
            wheelARAnchor = arAnchor
            arView.session.add(anchor: arAnchor)

            let ae = AnchorEntity(anchor: arAnchor)
            anchorEntity = ae
            arView.scene.addAnchor(ae)

            let root = Entity()
            root.name = "rr_content_root"
            contentRoot = root
            ae.addChild(root)

            let wg = Entity()
            wg.name = "rr_wheel_group"
            wheelGroup = wg
            root.addChild(wg)

            // clear cached entities
            oldRing = nil
            newRing = nil
            jackBase = nil
            jackLift = nil
            jackTop = nil
            lugEntities.removeAll()
            lugArrowEntities.removeAll()
            removedLugs.removeAll()
        }

        // MARK: - Oriented transform helper

        private func orientedTransform(from worldTransform: simd_float4x4) -> simd_float4x4 {
            let pos = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)

            // Candidate axes from raycast transform
            let xAxis = simd_normalize(SIMD3<Float>(worldTransform.columns.0.x, worldTransform.columns.0.y, worldTransform.columns.0.z))
            let yAxis = simd_normalize(SIMD3<Float>(worldTransform.columns.1.x, worldTransform.columns.1.y, worldTransform.columns.1.z))
            let zAxis = simd_normalize(SIMD3<Float>(worldTransform.columns.2.x, worldTransform.columns.2.y, worldTransform.columns.2.z))

            let worldUp = SIMD3<Float>(0, 1, 0)

            // Choose the axis most likely to be the surface normal:
            // - for floors: yAxis ~ worldUp
            // - for walls:  zAxis is typically horizontal (dot with worldUp small)
            let yDot = abs(simd_dot(yAxis, worldUp))
            let zDot = abs(simd_dot(zAxis, worldUp))
            let normalWorld: SIMD3<Float> = (yDot > 0.70) ? yAxis : zAxis

            var yN = simd_normalize(normalWorld)

            // Build an orthonormal basis: x = up × y (fallback if near-parallel)
            var xN = simd_cross(worldUp, yN)
            if simd_length(xN) < 1e-4 {
                xN = xAxis
            }
            xN = simd_normalize(xN)
            let zN = simd_normalize(simd_cross(yN, xN))

            var m = matrix_identity_float4x4
            m.columns.0 = SIMD4<Float>(xN.x, xN.y, xN.z, 0)
            m.columns.1 = SIMD4<Float>(yN.x, yN.y, yN.z, 0)   // local +Y = surface normal
            m.columns.2 = SIMD4<Float>(zN.x, zN.y, zN.z, 0)
            m.columns.3 = SIMD4<Float>(pos.x, pos.y, pos.z, 1)
            return m
        }
    }
}

