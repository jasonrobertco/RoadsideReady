import SwiftUI
import UIKit
import RealityKit
import ARKit
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ARViewContainer
// ─────────────────────────────────────────────────────────────────────────────
struct ARViewContainer: UIViewRepresentable {
    let currentStepID: String
    let lugCount: Int
    @ObservedObject var sessionModel: ARSessionModel
    let isActive: Bool

    init(currentStepID: String,
         lugCount: Int,
         sessionModel: ARSessionModel,
         isActive: Bool = true) {
        self.currentStepID = currentStepID
        self.lugCount      = lugCount
        self.sessionModel  = sessionModel
        self.isActive      = isActive
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let cfg = ARWorldTrackingConfiguration()
        cfg.planeDetection      = [.horizontal, .vertical]
        cfg.environmentTexturing = .automatic
        cfg.isAutoFocusEnabled  = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.attach(arView, config: cfg)
        context.coordinator.setActive(isActive)
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.setActive(isActive)
        context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionModel: sessionModel) }

    // ─────────────────────────────────────────────────────────────────────────
    final class Coordinator: NSObject, ARSessionDelegate {

        // ── external state ────────────────────────────────────────────────────
        private let sessionModel: ARSessionModel
        weak var arView: ARView?
        private var config: ARWorldTrackingConfiguration?
        private var sessionRunning = false

        // ── placement guard ───────────────────────────────────────────────────
        // Once placed, ONLY resetARSession() can clear this.
        private var isPlaced = false

        // ── scene hierarchy ───────────────────────────────────────────────────
        // ARAnchor → anchorEntity → contentRoot → wheelGroup (lifted by jack)
        private var wheelARAnchor: ARAnchor?
        private var anchorEntity:  AnchorEntity?
        private var contentRoot:   Entity?          // stays on surface
        private var wheelGroup:    Entity?           // moves up when jacked

        // ── tire entities ─────────────────────────────────────────────────────
        // "Old" flat tire (grey) and "spare" (blue), swapped at ft_mount
        private var tireOldTread: ModelEntity?   // thick black rubber torus
        private var tireOldHub:   ModelEntity?   // grey alloy hub face
        private var tireNewTread: ModelEntity?   // blue spare tread
        private var tireNewHub:   ModelEntity?   // blue hub face

        // ── jack entities (parented to contentRoot, beside tire) ──────────────
        private var jackBase: ModelEntity?
        private var jackBody: ModelEntity?
        private var jackPad:  ModelEntity?

        // ── lug entities ──────────────────────────────────────────────────────
        private var lugEntities:      [Int: ModelEntity] = [:]

        // ── animation / step state ────────────────────────────────────────────
        private enum Stage { case base, loosen, jackPlaced, jackUp, removed, mount, lowered }
        private var stage:         Stage  = .base
        private var lastStepID:    String = ""
        private var lastLugCount:  Int    = 0
        private var lastResetReq:  Int    = 0
        private var stageTask:     Task<Void, Never>?
        private var awaitingReset  = false

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Geometry constants  (all in metres, real-world scale)
        // ─────────────────────────────────────────────────────────────────────

        // ── Tire cross-section (roughly 205/55 R16 scale ~0.65 m outer dia.) ─
        // The model is placed flat, looking face-on.
        // Local +Y  = surface normal (pointing toward camera when placed on floor)
        // The tread annulus: outer radius 0.215 m, inner radius 0.155 m (rim seat)
        // Sidewall height (half the tread depth) = 0.060 m  → total width 0.120 m
        private let treadOuterR: Float = 0.215
        private let treadInnerR: Float = 0.155   // rim/bead seat
        private let treadHalfW:  Float = 0.060   // half sidewall width

        private let tireY: Float = 0

        // Hub (alloy wheel face) sits just inside the bead seat, slightly proud
        private let hubR:        Float = 0.150   // radius of visible hub face
        private let hubThick:    Float = 0.014   // hub face thickness

        // Lug bolt circle: 5×114.3 mm PCD → ~0.057 m radius
        private let lugBCR:      Float = 0.080   // bolt circle radius (just inside hubR)

        // Vertical offsets in local frame (local Y = normal toward camera)
        // Everything lives in the X-Z plane at the appropriate Y
        private lazy var lugY:   Float = treadHalfW + hubThick + (lugHeadH * 0.5) + 0.004   // ~0.084

        // Jack sits to the side in local X; only visible during jack steps
        private let jackGap: Float = 0.002
        private let jackRetractedDrop: Float = 0.060

        private let jackLiftH: Float = 0.085  // how far wheelGroup moves up

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Lug bolt dimensions
        // ─────────────────────────────────────────────────────────────────────
        private let lugHeadH: Float = 0.012
        private let lugHeadR: Float = 0.014
        private let lugStemH: Float = 0.036  // 3× head height
        private let lugStemR: Float = 0.006

        // Remove animation: lugs fly ~1 ft (0.30 m) along local +Y
        private let lugFlyDist: Float = 0.30

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Lazy meshes  (built once, on first use)
        // ─────────────────────────────────────────────────────────────────────
        private lazy var tireOuterMesh: MeshResource =
                    MeshResource.generateCylinder(height: treadHalfW * 2, radius: treadOuterR)
        private lazy var tireInnerMesh: MeshResource =
            MeshResource.generateCylinder(height: treadHalfW * 2 + 0.004, radius: treadInnerR)
        private let matRimBarrel = SimpleMaterial(
                    color: UIColor(white: 0.75, alpha: 1.0), isMetallic: false)
        private let matRimBarrelNew = SimpleMaterial(
                    color: UIColor(hue: 0.60, saturation: 0.55, brightness: 0.70, alpha: 1.0),
                    isMetallic: false)
    
        private lazy var hubMesh: MeshResource =
            MeshResource.generateCylinder(height: hubThick, radius: hubR)

        private lazy var lugHeadMesh: MeshResource =
            Self.makeHexPrismMesh(height: lugHeadH, radius: lugHeadR)

        private lazy var lugStemMesh: MeshResource =
            MeshResource.generateCylinder(height: lugStemH, radius: lugStemR)

        private let jackBaseMesh = MeshResource.generateBox(size: [0.09, 0.016, 0.09])
        private let jackBodyMesh = MeshResource.generateBox(size: [0.032, 0.060, 0.032])
        private let jackPadMesh  = MeshResource.generateBox(size: [0.060, 0.012, 0.060])

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Materials
        // ─────────────────────────────────────────────────────────────────────
        // Tyre rubber — nearly opaque matte black
        private let matRubber = SimpleMaterial(
            color: UIColor(white: 0.06, alpha: 0.97), isMetallic: false)
        // Spare tyre — dark blue rubber
        private let matSpareRubber = SimpleMaterial(
            color: UIColor(hue: 0.60, saturation: 0.80, brightness: 0.55, alpha: 0.95),
            isMetallic: false)
        // Alloy wheel hub — medium grey metallic
        private let matAlloy = SimpleMaterial(
            color: UIColor(white: 0.60, alpha: 1.0), isMetallic: false)
        // Spare hub — blue metallic
        private let matAlloyNew = SimpleMaterial(
            color: UIColor(hue: 0.60, saturation: 0.55, brightness: 0.70, alpha: 1.0),
            isMetallic: false)
        // Lug nut states
        private let matLugBlue   = SimpleMaterial(color: .systemBlue,   isMetallic: true)
        private let matLugOrange = SimpleMaterial(color: .systemOrange,  isMetallic: true)
        private let matLugRed    = SimpleMaterial(color: .systemRed,     isMetallic: true)
        // Jack
        private let matJack = SimpleMaterial(
            color: UIColor(white: 0.16, alpha: 0.93), isMetallic: true)

        // ─────────────────────────────────────────────────────────────────────
        init(sessionModel: ARSessionModel) {
            self.sessionModel = sessionModel
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Session management
        // ─────────────────────────────────────────────────────────────────────
        func attach(_ arView: ARView, config: ARWorldTrackingConfiguration) {
            self.arView  = arView
            self.config  = config
            arView.session.delegate = self
        }

        func setActive(_ active: Bool) {
            guard let arView, let config else { return }
            guard active != sessionRunning else { return }
            sessionRunning = active
            if active { arView.session.run(config) }
            else      { arView.session.pause() }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Main update  (called every SwiftUI render)
        // ─────────────────────────────────────────────────────────────────────
        func update(stepID: String, lugCount: Int) {
            // 1) Redo takes absolute priority
            if sessionModel.resetRequest != lastResetReq {
                lastResetReq = sessionModel.resetRequest
                resetARSession()
                return
            }

            // 2) Keep model's lug count in sync with slider (idempotent guard inside)
            if sessionModel.expectedLugCount != lugCount {
                sessionModel.setExpectedLugCount(lugCount)
            }

            // 3) Recover anchor if scene lost it (e.g. background/foreground)
            syncAnchorFromModelIfNeeded()

            // 4) Nothing placed yet — nothing to do
            guard isPlaced, wheelGroup != nil else { return }

            // 5) Ensure static tire + jack geometry exists
            buildStaticGeometryIfNeeded()

            // 6) Lug count changed → rebuild lug ring
            let confirmedAndLocked = sessionModel.lugSetupConfirmed && sessionModel.isLocked
            if confirmedAndLocked && lugCount != lastLugCount {
                lastLugCount = lugCount
                rebuildLugs(count: lugCount)
            }

            // 7) Setup just became confirmed → spawn lugs for first time
            if confirmedAndLocked && lugEntities.isEmpty {
                lastLugCount = lugCount
                rebuildLugs(count: lugCount)
            }

            // 8) Step changed → drive stage machine
            if stepID != lastStepID {
                lastStepID = stepID
                driveStage(to: stageForStep(stepID))
            }

            // 9) Passive refresh (tighten highlights, etc.)
            refreshLugMaterials()
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Tap handler
        // ─────────────────────────────────────────────────────────────────────
        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView else { return }
            let loc = sender.location(in: arView)
            showTapFeedback(in: arView, at: loc)

            // ── Lug taps ────────────────────────────────────────────────────
            if sessionModel.isLocked,
               sessionModel.lugSetupConfirmed,
               let entity = arView.entity(at: loc),
               entity.name.hasPrefix("rr_lug_"),
               let idx = Int(entity.name.dropFirst("rr_lug_".count)) {

                let tightenSteps: Set<String> = ["ft_mount", "ft_lower", "ft_aftercare"]
                if lastStepID == "ft_loosen" {
                    sessionModel.toggleLoosened(idx)
                } else if tightenSteps.contains(lastStepID) {
                    sessionModel.handleTightenTap(idx)
                }
                refreshLugMaterials()
                return
            }

            // ── Already placed — lock out further tap placement ──────────────
            if isPlaced {
                sessionModel.setStatus("Locked. Use ↺ to reposition.")
                autoHideStatus(after: 1.5)
                return
            }

            // ── First placement ──────────────────────────────────────────────
            guard let hit = bestRaycastHit(in: arView, at: loc) else {
                sessionModel.setStatus("No surface found. Slowly scan floor or wall.")
                autoHideStatus(after: 2.0)
                return
            }

            commitPlacement(from: hit)
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Placement  (one-shot, locked until Redo)
        // ─────────────────────────────────────────────────────────────────────
        private func commitPlacement(from hit: ARRaycastResult) {
            guard let arView else { return }

            // Build oriented transform: local +Y = surface normal (floor & wall safe)
            let camPos = arView.cameraTransform.translation
            let t = orientedTransform(from: hit.worldTransform, cameraPos: camPos)

            // Remove any previous anchor
            if let old = wheelARAnchor { arView.session.remove(anchor: old) }
            anchorEntity?.removeFromParent()

            // Create a tracked ARAnchor (stays stable as tracking refines)
            let ara = ARAnchor(transform: t)
            wheelARAnchor = ara
            arView.session.add(anchor: ara)

            let ae = AnchorEntity(anchor: ara)
            anchorEntity = ae
            arView.scene.addAnchor(ae)

            // contentRoot: never moves (stays flush with surface)
            let root = Entity(); root.name = "rr_content_root"
            contentRoot = root
            ae.addChild(root)

            // wheelGroup: lifted by jack animation
            let wg = Entity(); wg.name = "rr_wheel_group"
            wheelGroup = wg
            root.addChild(wg)

            // Reset all entity caches
            tireOldTread = nil; tireOldHub = nil
            tireNewTread = nil; tireNewHub = nil
            jackBase = nil; jackBody = nil; jackPad = nil
            lugEntities.removeAll()
            stage = .base
            lastStepID = ""
            lastLugCount = 0

            // Tell the model
            sessionModel.setAnchor(t)
            sessionModel.lock()

            isPlaced = true  // ← only Redo can clear this

            // Build static geometry immediately
            buildStaticGeometryIfNeeded()

            sessionModel.setStatus("Placed ✓  •  Set lug count to continue")
            autoHideStatus(after: 2.5)
        }

        private func syncAnchorFromModelIfNeeded() {
            // If scene lost the anchor entity but model still has a transform, restore it
            guard !isPlaced, anchorEntity == nil,
                  let t = sessionModel.wheelTransform,
                  let arView else { return }

            let ara = ARAnchor(transform: t)
            wheelARAnchor = ara
            arView.session.add(anchor: ara)

            let ae = AnchorEntity(anchor: ara)
            anchorEntity = ae
            arView.scene.addAnchor(ae)

            let root = Entity(); root.name = "rr_content_root"
            contentRoot = root; ae.addChild(root)

            let wg = Entity(); wg.name = "rr_wheel_group"
            wheelGroup = wg; root.addChild(wg)

            isPlaced = true
            buildStaticGeometryIfNeeded()
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Static geometry  (tire + jack, built once)
        // ─────────────────────────────────────────────────────────────────────
        private func buildStaticGeometryIfNeeded() {
            buildTireIfNeeded()
            buildJackIfNeeded()
        }

        private func buildTireIfNeeded() {
            guard let wg = wheelGroup, tireOldTread == nil else { return }

            // OLD tire: black outer cylinder + silver inner cylinder
            let oldOuter = ModelEntity(mesh: tireOuterMesh, materials: [matRubber])
            oldOuter.name = "rr_tire_old_tread"
            oldOuter.position = [0, tireY, 0]
            tireOldTread = oldOuter
            wg.addChild(oldOuter)

            let oldInner = ModelEntity(mesh: tireInnerMesh, materials: [matRimBarrel])
            oldInner.name = "rr_tire_old_inner"
            oldInner.position = [0, tireY, 0]
            wg.addChild(oldInner)

            let oldHub = ModelEntity(mesh: hubMesh, materials: [matAlloy])
            oldHub.name = "rr_tire_old_hub"
            oldHub.position = [0, treadHalfW + hubThick * 0.5, 0]
            tireOldHub = oldHub
            wg.addChild(oldHub)

            // SPARE tire: dark blue outer + blue inner
            let newOuter = ModelEntity(mesh: tireOuterMesh, materials: [matSpareRubber])
            newOuter.name = "rr_tire_new_tread"
            newOuter.position = [0, tireY, 0]
            newOuter.isEnabled = false
            tireNewTread = newOuter
            wg.addChild(newOuter)

            let newInner = ModelEntity(mesh: tireInnerMesh, materials: [matRimBarrelNew])
            newInner.name = "rr_tire_new_inner"
            newInner.position = [0, tireY, 0]
            newInner.isEnabled = false
            wg.addChild(newInner)

            let newHub = ModelEntity(mesh: hubMesh, materials: [matAlloyNew])
            newHub.name = "rr_tire_new_hub"
            newHub.position = [0, treadHalfW + hubThick * 0.5, 0]
            newHub.isEnabled = false
            tireNewHub = newHub
            wg.addChild(newHub)
        }

        private func buildJackIfNeeded() {
            guard let root = contentRoot, jackBase == nil else { return }

            let base = ModelEntity(mesh: jackBaseMesh, materials: [matJack])
            base.name = "rr_jack_base"
            base.position = .zero
            base.isEnabled = false
            jackBase = base
            root.addChild(base)

            let body = ModelEntity(mesh: jackBodyMesh, materials: [matJack])
            body.name = "rr_jack_body"
            body.position = .zero
            body.isEnabled = false
            jackBody = body
            root.addChild(body)

            let pad = ModelEntity(mesh: jackPadMesh, materials: [matJack])
            pad.name = "rr_jack_pad"
            pad.position = .zero   // baseline; we animate vertical in world-up later
            pad.isEnabled = false
            jackPad = pad
            root.addChild(pad)
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Lug build  (called when lugCount confirmed or changes)
        // ─────────────────────────────────────────────────────────────────────
        private func rebuildLugs(count: Int) {
            // Clear any tighten state when lug count changes
            sessionModel.tightenedLugs.removeAll()
            sessionModel.activeLugIndex = nil

            guard let wg = wheelGroup else { return }

            // Disable all existing lugs first
            for (_, e) in lugEntities      { e.isEnabled = false }

            let positions = lugPositions(count: count)

            for i in 0..<count {
                // Lug bolt
                if lugEntities[i] == nil {
                    let head = ModelEntity(mesh: lugHeadMesh, materials: [matLugBlue])
                    head.name = "rr_lug_\(i)"
                    head.components.set(InputTargetComponent())
                    head.generateCollisionShapes(recursive: true)

                    let stem = ModelEntity(mesh: lugStemMesh, materials: [matLugBlue])
                    stem.name = "rr_lug_stem"
                    // stem hangs below head: offset = -(headH/2 + stemH/2)
                    stem.position = [0, -(lugHeadH * 0.5 + lugStemH * 0.5), 0]
                    head.addChild(stem)

                    lugEntities[i] = head
                    wg.addChild(head)
                }

                let lug = lugEntities[i]!
                lug.isEnabled = true
                lug.transform = Transform(translation: positions[i])
                setLugMat(lug, matLugBlue)
            }

            // Apply current stage to newly built lugs
            snapLugsToStage(animated: false)
        }

        // Lug bolt circle positions in local space
        private func lugPositions(count: Int) -> [SIMD3<Float>] {
            guard count > 0 else { return [] }
            return (0..<count).map { i in
                let angle = Float(i) * (2 * .pi / Float(count))
                return [lugBCR * cos(angle), lugY, lugBCR * sin(angle)]
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Stage machine
        // ─────────────────────────────────────────────────────────────────────
        private func stageForStep(_ id: String) -> Stage {
            switch id {
            case "ft_loosen":                  return .loosen
            case "ft_jackpoint":               return .jackPlaced
            case "ft_jackup":                  return .jackUp
            case "ft_remove":                  return .removed
            case "ft_mount":                   return .mount
            case "ft_lower", "ft_aftercare":   return .lowered
            default:                           return .base
            }
        }

        private func driveStage(to target: Stage) {
            let prev = stage
            stage = target

            // Auto-confirm lug setup if user somehow navigated past the UI step
            if !sessionModel.lugSetupConfirmed {
                sessionModel.confirmLugSetup(sessionModel.expectedLugCount)
            }
            // Ensure lugs exist (setup may have just confirmed above)
            if lugEntities.isEmpty {
                lastLugCount = sessionModel.expectedLugCount
                rebuildLugs(count: lastLugCount)
            }

            stageTask?.cancel()
            stageTask = Task { @MainActor in
                await runStageAnimation(from: prev, to: target)
            }
        }

        private func runStageAnimation(from: Stage, to: Stage) async {
            guard !Task.isCancelled else { return }

            // ── Jack visibility + extension ────────────────────────────────────
            let showJack    = (to == .jackPlaced || to == .jackUp ||
                               to == .removed    || to == .mount)
            let extendJack  = (to == .jackUp || to == .removed || to == .mount)

            let lift: Float = extendJack ? jackLiftH : 0

            jackBase?.isEnabled = showJack
            jackBody?.isEnabled = showJack
            jackPad?.isEnabled  = showJack

            if showJack, let root = contentRoot {
                // wheel center in WORLD (same world X/Z axis you want)
                let worldRoot = root.convert(position: [0, 0, 0], to: nil)
                let wheelCenterWorld = SIMD3<Float>(worldRoot.x, worldRoot.y + lift, worldRoot.z)

                // bottom point of tire in WORLD
                let bottomY = wheelCenterWorld.y - treadOuterR

                // jack pad height = 0.012 -> half = 0.006
                let padHalfH: Float = 0.006

                let padY = extendJack
                    ? (bottomY - jackGap - padHalfH)
                    : (bottomY - jackRetractedDrop)

                func moveWorld(_ e: Entity?, _ world: SIMD3<Float>, _ dur: Double) {
                    guard let e else { return }
                    let local = root.convert(position: world, from: nil)
                    e.move(to: Transform(translation: local),
                           relativeTo: root,
                           duration: dur,
                           timingFunction: .easeInOut)
                }

                moveWorld(jackPad,  [wheelCenterWorld.x, padY,            wheelCenterWorld.z], 0.50)
                moveWorld(jackBody, [wheelCenterWorld.x, padY - 0.045,    wheelCenterWorld.z], 0.50)
                moveWorld(jackBase, [wheelCenterWorld.x, padY - 0.085,    wheelCenterWorld.z], 0.25)
            }

            // ── Wheel lift (world +Y) ─────────────────────────────────────────
            if let wg = wheelGroup, let root = contentRoot {
                // let lift: Float = extendJack ? jackLiftH : 0   <-- removed this line as per instructions
                // Compute a world-space target directly above the root, then convert back to root local
                let worldBase = root.convert(position: [0, 0, 0], to: nil)
                let worldTarget = SIMD3<Float>(worldBase.x, worldBase.y + lift, worldBase.z)
                let localTarget = root.convert(position: worldTarget, from: nil)
                wg.move(to: Transform(translation: localTarget),
                        relativeTo: contentRoot, duration: 0.55,
                        timingFunction: .easeInOut)
            }

            // ── Tyre swap ──────────────────────────────────────────────────────
            let showSpare = (to == .mount || to == .lowered)
            for e in wheelGroup?.children.filter({ $0.name.contains("old") }) ?? [] {
                e.isEnabled = !showSpare
            }
            for e in wheelGroup?.children.filter({ $0.name.contains("new") }) ?? [] {
                e.isEnabled = showSpare
            }

            // ── Lug animations ─────────────────────────────────────────────────
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }

            await animateLugsToStage(to)

            // Start tighten sequence on mount
            // Removed as requested
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Lug positioning helpers
        // ─────────────────────────────────────────────────────────────────────
        private func animateLugsToStage(_ target: Stage) async {
            let n = sessionModel.expectedLugCount
            let bases = lugPositions(count: n)

            for i in 0..<n {
                if Task.isCancelled { return }
                guard let lug = lugEntities[i], i < bases.count else { continue }

                let base   = bases[i]
                let radial = simd_normalize(SIMD3<Float>(base.x, 0, base.z))
                let (pos, rot, mat) = lugTransform(base: base, radial: radial,
                                                   stage: target, index: i)

                lug.move(to: Transform(scale: .one, rotation: rot, translation: pos),
                         relativeTo: wheelGroup, duration: 0.28,
                         timingFunction: .easeInOut)
                setLugMat(lug, mat)

                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }

        private func snapLugsToStage(animated: Bool) {
            let n = sessionModel.expectedLugCount
            let bases = lugPositions(count: n)

            for i in 0..<n {
                guard let lug = lugEntities[i], i < bases.count else { continue }
                let base   = bases[i]
                let radial = simd_normalize(SIMD3<Float>(base.x, 0, base.z))
                let (pos, rot, mat) = lugTransform(base: base, radial: radial,
                                                   stage: stage, index: i)

                if animated {
                    lug.move(to: Transform(scale: .one, rotation: rot, translation: pos),
                             relativeTo: wheelGroup, duration: 0.20,
                             timingFunction: .easeInOut)
                } else {
                    lug.transform = Transform(scale: .one, rotation: rot, translation: pos)
                }
                setLugMat(lug, mat)
            }
        }

        private func lugTransform(base: SIMD3<Float>,
                                   radial: SIMD3<Float>,
                                   stage: Stage,
                                   index: Int) -> (SIMD3<Float>, simd_quatf, SimpleMaterial) {
            switch stage {
            case .base:
                return (base,
                        simd_quatf(angle: 0, axis: [0, 1, 0]),
                        matLugBlue)

            case .loosen, .jackPlaced, .jackUp:
                // Slight radial outward + ~18° rotation
                let out = SIMD3<Float>(base.x + radial.x * 0.016,
                                       base.y,
                                       base.z + radial.z * 0.016)
                return (out,
                        simd_quatf(angle: .pi / 10, axis: [0, 1, 0]),
                        matLugOrange)

            case .removed:
                // Fly up along local +Y (~1 ft)
                let up = SIMD3<Float>(base.x, base.y + lugFlyDist, base.z)
                return (up,
                        simd_quatf(angle: .pi / 10, axis: [0, 1, 0]),
                        matLugRed)

            case .mount, .lowered:
                return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), matLugBlue)
            }
        }

        private func refreshLugMaterials() {
            let n = sessionModel.expectedLugCount
            let bases = lugPositions(count: n)
            for i in 0..<n {
                guard let lug = lugEntities[i], i < bases.count else { continue }
                let base   = bases[i]
                let radial = simd_normalize(SIMD3<Float>(base.x, 0, base.z))
                let (_, _, mat) = lugTransform(base: base, radial: radial,
                                               stage: stage, index: i)
                setLugMat(lug, mat)
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Utility
        // ─────────────────────────────────────────────────────────────────────
        private func setLugMat(_ head: ModelEntity, _ mat: SimpleMaterial) {
            head.model?.materials = [mat]
            if let stem = head.findEntity(named: "rr_lug_stem") as? ModelEntity {
                stem.model?.materials = [mat]
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Reset  (the ONLY path that clears isPlaced)
        // ─────────────────────────────────────────────────────────────────────
        private func resetARSession() {
            guard let arView, let config else { return }

            stageTask?.cancel(); stageTask = nil

            if let old = wheelARAnchor { arView.session.remove(anchor: old) }
            wheelARAnchor = nil

            anchorEntity?.removeFromParent()
            anchorEntity = nil; contentRoot = nil; wheelGroup = nil

            tireOldTread = nil; tireOldHub = nil
            tireNewTread = nil; tireNewHub = nil
            jackBase = nil; jackBody = nil; jackPad = nil
            lugEntities.removeAll()

            stage = .base
            lastStepID = ""
            lastLugCount = 0
            isPlaced = false   // ← unlocks placement

            sessionModel.resetAlignment()
            sessionModel.setStatus("Resetting AR…", phase: .resetting)

            awaitingReset = true
            arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }

        func session(_ session: ARSession,
                     cameraDidChangeTrackingState camera: ARCamera) {
            guard awaitingReset else { return }
            if case .normal = camera.trackingState {
                awaitingReset = false
                Task { @MainActor in
                    self.sessionModel.setStatus("Ready — tap a surface to place",
                                               phase: .ready)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self.sessionModel.setStatus(nil, phase: .none)
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Raycast  (floor + wall, with fallback)
        // ─────────────────────────────────────────────────────────────────────
        private func bestRaycastHit(in arView: ARView, at loc: CGPoint) -> ARRaycastResult? {
            let tries: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment, Float)] = [
                (.existingPlaneGeometry, .any,  3.5),
                (.existingPlaneInfinite, .any,  3.5),
                (.estimatedPlane,        .any,  1.8),
            ]
            for (target, alignment, maxD) in tries {
                guard let q = arView.makeRaycastQuery(from: loc, allowing: target,
                                                       alignment: alignment) else { continue }
                if let r = arView.session.raycast(q).first {
                    let p = r.worldTransform.columns.3
                    let d = simd_length(SIMD3<Float>(p.x, p.y, p.z)
                                        - arView.cameraTransform.translation)
                    if d < maxD { return r }
                }
            }
            return nil
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Oriented transform  (floor & wall safe)
        // ─────────────────────────────────────────────────────────────────────
        private func orientedTransform(from w: simd_float4x4, cameraPos: SIMD3<Float>) -> simd_float4x4 {
            let pos     = SIMD3<Float>(w.columns.3.x, w.columns.3.y, w.columns.3.z)
            let yRaw    = simd_normalize(SIMD3<Float>(w.columns.1.x, w.columns.1.y, w.columns.1.z))
            let zRaw    = simd_normalize(SIMD3<Float>(w.columns.2.x, w.columns.2.y, w.columns.2.z))
            let worldUp = SIMD3<Float>(0, 1, 0)

            let normal: SIMD3<Float> =
                abs(simd_dot(yRaw, worldUp)) >= abs(simd_dot(zRaw, worldUp)) ? yRaw : -zRaw

            let isFloor = abs(simd_dot(normal, worldUp)) > 0.7

            let xN: SIMD3<Float>
            let yN: SIMD3<Float>
            let zN: SIMD3<Float>

            if isFloor {
                // Wheel stands upright on floor, face toward camera.
                // Local +Y = face normal (horizontal toward camera), local +Z = worldUp.
                let toCamera = SIMD3<Float>(cameraPos.x - pos.x, 0, cameraPos.z - pos.z)
                let faceNorm = simd_length(toCamera) > 1e-4
                    ? simd_normalize(toCamera)
                    : SIMD3<Float>(0, 0, 1)
                yN = faceNorm
                zN = worldUp
                xN = simd_normalize(simd_cross(yN, zN))
            } else {
                // Wall: local +Y = surface normal toward camera
                yN = simd_normalize(normal)
                var x = simd_cross(worldUp, yN)
                if simd_length(x) < 1e-4 {
                    x = SIMD3<Float>(w.columns.0.x, w.columns.0.y, w.columns.0.z)
                }
                xN = simd_normalize(x)
                zN = simd_normalize(simd_cross(yN, xN))
            }

            var m = matrix_identity_float4x4
            m.columns.0 = SIMD4<Float>(xN.x, xN.y, xN.z, 0)
            m.columns.1 = SIMD4<Float>(yN.x, yN.y, yN.z, 0)
            m.columns.2 = SIMD4<Float>(zN.x, zN.y, zN.z, 0)
            m.columns.3 = SIMD4<Float>(pos.x, pos.y, pos.z, 1)
            return m
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Mesh generators
        // ─────────────────────────────────────────────────────────────────────

        /// Annular tyre tread: hollow cylinder with outer+inner walls, top+bottom caps.
        /// Y-axis = tyre rotational axis (ring lies in X-Z plane, facing +Y).
        /// halfWidth is half the sidewall height (total axle-to-axle thickness = 2×halfWidth).
        private static func makeAnnulusMesh(halfWidth: Float,
                                             innerR: Float,
                                             outerR: Float,
                                             segments: Int) -> MeshResource {
            let n   = max(24, segments)
            let h   = halfWidth  // local Y half-extent
            var pos: [SIMD3<Float>] = []
            pos.reserveCapacity(n * 4)

            // 4 vertices per segment column: top-outer, top-inner, bot-outer, bot-inner
            for i in 0..<n {
                let a = Float(i) / Float(n) * 2 * .pi
                let c = cos(a), s = sin(a)
                pos.append([outerR * c,  h, outerR * s])   // top outer
                pos.append([innerR * c,  h, innerR * s])   // top inner
                pos.append([outerR * c, -h, outerR * s])   // bot outer
                pos.append([innerR * c, -h, innerR * s])   // bot inner
            }

            var idx: [UInt32] = []
            idx.reserveCapacity(n * 24)

            for i in 0..<n {
                let cur = UInt32(i * 4)
                let nxt = UInt32(((i + 1) % n) * 4)
                let to0=cur+0, ti0=cur+1, bo0=cur+2, bi0=cur+3
                let to1=nxt+0, ti1=nxt+1, bo1=nxt+2, bi1=nxt+3

                // Top cap  (CCW from +Y)
                idx += [to0, to1, ti1,  to0, ti1, ti0]
                // Bottom cap (CCW from -Y)
                idx += [bo0, bi0, bi1,  bo0, bi1, bo1]
                // Outer wall (CCW from outside)
                idx += [to0, bo1, bo0,  to0, to1, bo1]
                // Inner wall (CCW from inside = reversed)
                idx += [ti0, bi0, bi1,  ti0, bi1, ti1]
            }

            var desc = MeshDescriptor()
            desc.positions  = MeshBuffers.Positions(pos)
            desc.primitives = .triangles(idx)

            do    { return try MeshResource.generate(from: [desc]) }
            catch { return .generateCylinder(height: halfWidth * 2, radius: outerR) }
        }

        /// Hexagonal prism for lug head. Y = prism axis.
        private static func makeHexPrismMesh(height: Float, radius: Float) -> MeshResource {
            let h = height / 2
            var positions: [SIMD3<Float>] = []
            for i in 0..<6 {
                let a = Float(i) * (.pi / 3)
                positions.append([radius * cos(a), -h, radius * sin(a)])
            }
            for i in 0..<6 {
                let a = Float(i) * (.pi / 3)
                positions.append([radius * cos(a),  h, radius * sin(a)])
            }
            positions.append([0, -h, 0])  // 12: bottom centre
            positions.append([0,  h, 0])  // 13: top centre

            var idx: [UInt32] = []
            for i: UInt32 in 0..<6 {
                let b0=i, b1=(i+1)%6, t0=i+6, t1=((i+1)%6)+6
                idx += [b0, t0, t1,  b0, t1, b1]
            }
            for i: UInt32 in 0..<6 { idx += [12, (i+1)%6, i] }
            for i: UInt32 in 0..<6 { idx += [13, i+6, ((i+1)%6)+6] }

            var desc = MeshDescriptor()
            desc.positions  = MeshBuffers.Positions(positions)
            desc.primitives = .triangles(idx)

            do    { return try MeshResource.generate(from: [desc]) }
            catch { return .generateCylinder(height: height, radius: radius) }
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Tap feedback
        // ─────────────────────────────────────────────────────────────────────
        private func showTapFeedback(in arView: ARView, at pt: CGPoint) {
            let sz: CGFloat = 12
            let dot = UIView(frame: CGRect(x: pt.x - sz/2, y: pt.y - sz/2,
                                          width: sz, height: sz))
            dot.backgroundColor = .systemBlue
            dot.layer.cornerRadius = sz / 2
            dot.alpha = 0.9
            dot.isUserInteractionEnabled = false
            dot.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            arView.addSubview(dot)

            UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut) {
                dot.transform = .identity
            }
            UIView.animate(withDuration: 0.35, delay: 0.12, options: .curveEaseIn) {
                dot.alpha = 0; dot.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
            } completion: { _ in dot.removeFromSuperview() }
        }

        private func autoHideStatus(after secs: Double) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                self.sessionModel.setStatus(nil, phase: .none)
            }
        }
    }
}

