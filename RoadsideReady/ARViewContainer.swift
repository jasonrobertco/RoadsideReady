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
        cfg.environmentTexturing = .none
        cfg.isAutoFocusEnabled  = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.attach(arView, config: cfg)
        context.coordinator.setActive(isActive)
        DispatchQueue.main.async {
            context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.setActive(isActive)
        DispatchQueue.main.async {
            context.coordinator.update(stepID: currentStepID, lugCount: lugCount)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionModel: sessionModel) }

    // ─────────────────────────────────────────────────────────────────────────
    final class Coordinator: NSObject, ARSessionDelegate {

        // ── external state ────────────────────────────────────────────────────
        private let sessionModel: ARSessionModel
        weak var arView: ARView?
        private var config: ARWorldTrackingConfiguration?
        private var sessionRunning = false

        // ── lug entities ──────────────────────────────────────────────────────
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

        private var canonicalTireLocal: [String: Transform] = [:]
        private var oldTireIsDetached = false

        // ── jack entities (scissor jack under the tire) ─────────────────────
        private var jackRoot: Entity?
        private var jackBase: ModelEntity?
        private var jackTop:  ModelEntity?
        private var jackArmLF: ModelEntity?
        private var jackArmRF: ModelEntity?
        private var jackArmLB: ModelEntity?
        private var jackArmRB: ModelEntity?
        private var jackPad:  ModelEntity?
        private var jackPointMarker: ModelEntity? 
        private var jackFlashTask: Task<Void, Never>?
        private var chockMarker: ModelEntity?
        private var chockFlashTask: Task<Void, Never>?
        private var lugsAnimatedInStage: Set<Int> = [] 

        // ── lug entities ──────────────────────────────────────────────────────
        private var lugEntities: [Int: Entity] = [:]

        // ── animation / step state ────────────────────────────────────────────
        private enum Stage { case base, chockPlaced, loosen, jackPlaced, jackUp, removed, mount, lowered }
        private var stage:         Stage  = .base
        private var lastStepID:    String = ""
        private var lastLugCount:  Int    = 0
        private var lastResetReq:  Int    = 0
        private var stageTask:     Task<Void, Never>?
        private var awaitingReset  = false
        private var statusTask: Task<Void, Never>?

        private var observers: [NSObjectProtocol] = []

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
        // Placed 5mm proud of the hub face (treadHalfW + hubThick)
        private lazy var lugY:   Float = (treadHalfW + hubThick) + 0.005

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

        private let tirePullDist: Float = 0.30    // how far tire pulls off along normal
        private let tirePullDur: Double = 0.45
        private let tireFlyInDur: Double = 0.55

        // Dead tire placement constants
        private let deadTireSideMeters: Float = 0.34   // how far to the side
        private let deadTireDownMeters: Float = 0.12   // how far down to "ground"
        private let deadTireFlatScaleY: Float = 0.25   // visually "flat"

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

        private let lugTickMesh = MeshResource.generateBox(size: [0.006, 0.003, 0.003])

        private let jackBaseMesh = MeshResource.generateBox(size: [0.26, 0.008, 0.16])
        private let jackTopMesh  = MeshResource.generateBox(size: [0.12, 0.010, 0.08])
        private let jackPadMesh  = MeshResource.generateBox(size: [0.070, 0.012, 0.070])

        // Unit arm (length 1). We scale X to desired length at runtime.
        private let jackArmUnitMesh = MeshResource.generateBox(size: [1.0, 0.010, 0.012])

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Materials
        // ─────────────────────────────────────────────────────────────────────
        // Tyre rubber — nearly opaque matte black
        private let matRubber = SimpleMaterial(
            color: UIColor(white: 0.06, alpha: 0.97), isMetallic: false)
        // Spare tyre outer — black rubber (same as flat tyre)
        private let matSpareRubber = SimpleMaterial(
            color: UIColor(white: 0.06, alpha: 0.97), isMetallic: false)
        // Alloy wheel hub — medium grey metallic
        private let matAlloy = SimpleMaterial(
            color: UIColor(white: 0.60, alpha: 1.0), isMetallic: false)
        // Spare hub/rim — dark yellow (steel spare wheel colour)
        private let matAlloyNew = SimpleMaterial(
            color: UIColor(hue: 0.13, saturation: 0.70, brightness: 0.55, alpha: 1.0),
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

            let token = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.arView?.session.pause()
            }
            observers.append(token)
        }

        deinit {
            jackFlashTask?.cancel()
            chockFlashTask?.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
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
               let hitEntity = arView.entity(at: loc) {

                // Walk up to find the rr_lug_<i> container
                var e: Entity? = hitEntity
                while let cur = e, !cur.name.hasPrefix("rr_lug_") { e = cur.parent }
                if let lugContainer = e,
                   lugContainer.name.hasPrefix("rr_lug_"),
                   let idx = Int(lugContainer.name.dropFirst("rr_lug_".count)) {

                    let tightenSteps: Set<String> = ["ft_mount", "ft_lower", "ft_aftercare"]
                    if lastStepID == "ft_loosen" {
                        sessionModel.toggleLoosened(idx)
                    } else if tightenSteps.contains(lastStepID) {
                        sessionModel.handleTightenTap(idx)
                    }
                    refreshLugMaterials()
                    return
                }
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

        /// Resolve a tapped entity to its lug index by walking up to the container named "rr_lug_<index>".
        private func lugIndex(for entity: Entity) -> Int? {
            var e: Entity? = entity
            while let cur = e {
                if cur.name.hasPrefix("rr_lug_"),
                   let idx = Int(cur.name.dropFirst("rr_lug_".count)) {
                    return idx
                }
                e = cur.parent
            }
            return nil
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
            jackRoot = nil; jackBase = nil; jackTop = nil; jackPad = nil
            jackArmLF = nil; jackArmRF = nil; jackArmLB = nil; jackArmRB = nil
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
            buildChockIfNeeded()
        }
        
        private func buildChockIfNeeded() {
                    guard let root = contentRoot, chockMarker == nil else { return }
                    
                    let w: Float = 0.15 // width (side-to-side)
                    let h: Float = 0.12 // height (up)
                    let d: Float = 0.18 // depth (slope distance)
                    
                    var desc = MeshDescriptor()
                    // Fixed Profile: Triangular wedge sitting flat on the XY plane.
                    // Tall back wall is at Y=0, slope goes down to Y=d.
            desc.positions = MeshBuffers.Positions([
                [0, 0, 0], [w, 0, 0],     // 0,1: back bottom (Y = 0)
                [0, d, 0], [w, d, 0],     // 2,3: front bottom (Y = +d, toward camera)
                [0, 0, h], [w, 0, h]      // 4,5: back top    (Z = +h, up)
            ])

            desc.primitives = .triangles([
                // bottom
                0, 2, 3,   0, 3, 1,
                // back face
                0, 1, 5,   0, 5, 4,
                // sloped face
                4, 5, 3,   4, 3, 2,
                // left face (triangle)
                0, 2, 4,
                // right face (triangle)
                1, 3, 5
            ])
                    
                    var mat = PhysicallyBasedMaterial()
                    mat.baseColor = .init(tint: .systemYellow)
                    mat.emissiveColor = .init(color: .yellow)
                    mat.emissiveIntensity = 0.0
                    
                    let model = ModelEntity(mesh: (try? MeshResource.generate(from: [desc])) ?? .generateBox(size: 0.1), materials: [mat])
                    
            model.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) // 90° CCW
            let leftNudge: Float = -0.55   // try 0.05, 0.10, 0.15
            let forwardBackNudge: Float = -0.07   // try ±0.02, ±0.05, ±0.10

            model.position = [-(treadOuterR + w * 0.5 + 0.03 + leftNudge), forwardBackNudge, -treadOuterR]
                    
                    model.isEnabled = false
                    chockMarker = model
                    root.addChild(model)
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

            let newInner = ModelEntity(mesh: tireInnerMesh, materials: [matAlloyNew]) // dark yellow rim barrel
            newInner.name = "rr_tire_new_inner"
            newInner.position = [0, tireY, 0]
            newInner.isEnabled = false
            wg.addChild(newInner)

            let newHub = ModelEntity(mesh: hubMesh, materials: [matAlloyNew])          // dark yellow hub
            newHub.name = "rr_tire_new_hub"
            newHub.position = [0, treadHalfW + hubThick * 0.5, 0]
            newHub.isEnabled = false
            tireNewHub = newHub
            wg.addChild(newHub)

            if canonicalTireLocal.isEmpty {
                for name in ["rr_tire_old_tread","rr_tire_old_inner","rr_tire_old_hub",
                             "rr_tire_new_tread","rr_tire_new_inner","rr_tire_new_hub"] {
                    if let e = wheelGroup?.findEntity(named: name) {
                        canonicalTireLocal[name] = e.transform
                    }
                }
            }
        }

        private func buildJackIfNeeded() {
            guard let root = contentRoot, jackRoot == nil else { return }

            let jr = Entity()
            jr.name = "rr_jack_root"
            jr.isEnabled = false

            // 1. POSITION FIX:
            // -X (-0.22): Moved further left to correct the "offset to the right" look.
            // -Y (0.02): Brought closer to the wheel face so it's not too deep.
            // -Z (-treadOuterR): Kept at the bottom edge of the tire (the ground).
            jr.position = [-0.22, 0.02, -treadOuterR]

            // 2. ORIENTATION FIX:
            // Switched from -.pi/2 to +.pi/2.
            // This flips the jack 180 degrees back to an upright position so it lifts UP
            // toward the car instead of pushing down into the ground.
            jr.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

            jackRoot = jr
            root.addChild(jr)

            let base = ModelEntity(mesh: jackBaseMesh, materials: [matJack])
            base.name = "rr_jack_base"
            base.position = [0, 0.004, 0]
            jackBase = base
            jr.addChild(base)

            let top = ModelEntity(mesh: jackTopMesh, materials: [matJack])
            top.name = "rr_jack_top"
            top.position = [0, 0.06, 0]
            jackTop = top
            jr.addChild(top)

            func makeArm(_ name: String, z: Float) -> ModelEntity {
                let a = ModelEntity(mesh: jackArmUnitMesh, materials: [matJack])
                a.name = name
                a.position.z = z
                jr.addChild(a)
                return a
            }

            jackArmLF = makeArm("rr_jack_armLF", z:  0.020)
            jackArmRF = makeArm("rr_jack_armRF", z:  0.020)
            jackArmLB = makeArm("rr_jack_armLB", z: -0.020)
            jackArmRB = makeArm("rr_jack_armRB", z: -0.020)

            let pad = ModelEntity(mesh: jackPadMesh, materials: [matJack])
            pad.name = "rr_jack_pad"
            pad.position = [0, 0.075, 0]
            jackPad = pad
            jr.addChild(pad)
            
            // Fix: Use PhysicallyBasedMaterial to support glow intensity properties
            let markerMesh = MeshResource.generateBox(size: [0.08, 0.005, 0.08])
            var markerMat  = PhysicallyBasedMaterial()
            markerMat.baseColor = .init(tint: .red)
            markerMat.emissiveColor = .init(color: .red)
            markerMat.emissiveIntensity = 0.5
            let marker = ModelEntity(mesh: markerMesh, materials: [markerMat])
            marker.name = "rr_jack_point_marker"
            marker.isEnabled = false
            jackPointMarker = marker
            jr.addChild(marker)
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Lug build  (called when lugCount confirmed or changes)
        // ─────────────────────────────────────────────────────────────────────
        private func rebuildLugs(count: Int) {
            // Clear any tighten state when lug count changes
            sessionModel.tightenedLugs.removeAll()
            sessionModel.activeLugIndex = nil
            
            guard let wg = wheelGroup else { return }
            
            // Hard-remove lugs that are no longer needed (prevents accumulation)
            for k in lugEntities.keys where k >= count {
                lugEntities[k]?.removeFromParent()
                lugEntities[k] = nil
            }

            // Disable all existing lugs first
            for (_, e) in lugEntities      { e.isEnabled = false }

            let positions = lugPositions(count: count)

            for i in 0..<count {
                // Lug bolt
                if lugEntities[i] == nil {
                    let lug = Entity()
                    lug.name = "rr_lug_\(i)"
                    lug.components.set(InputTargetComponent())

                    let head = ModelEntity(mesh: lugHeadMesh, materials: [matLugBlue])
                    head.name = "rr_lug_head"
                    head.components.set(InputTargetComponent())
                    head.generateCollisionShapes(recursive: true)
                    lug.addChild(head)

                    let tick = ModelEntity(mesh: lugTickMesh, materials: [matLugBlue])
                    tick.name = "rr_lug_tick"
                    // place it near the edge of the hex so rotation is obvious
                    tick.position = [lugHeadR * 0.85, 0, 0]
                    head.addChild(tick)

                    let stem = ModelEntity(mesh: lugStemMesh, materials: [matLugBlue])
                    stem.name = "rr_lug_stem"
                    stem.position = [0, -(lugHeadH * 0.5 + lugStemH * 0.5), 0]
                    lug.addChild(stem)

                    lugEntities[i] = lug
                    wg.addChild(lug)
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
            case "ft_chock":                  return .chockPlaced
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
            
            // Start all nuts as Blue for the transition; persistence logic handles previous steps
            lugsAnimatedInStage.removeAll()

            // Auto-confirm lug setup if user somehow navigated past the UI step
            if !sessionModel.lugSetupConfirmed {
                sessionModel.confirmLugSetup(sessionModel.expectedLugCount)
            }
            // Ensure lugs exist (setup may have just confirmed above)
            if lugEntities.isEmpty {
                lastLugCount = sessionModel.expectedLugCount
                rebuildLugs(count: lastLugCount)
            }
            
            applyStageBaseline(target)

            stageTask?.cancel()
            stageTask = Task { @MainActor in
                await runStageAnimation(from: prev, to: target)
            }
        }

        private func runStageAnimation(from: Stage, to: Stage) async {
            guard !Task.isCancelled else { return }
            applyStageBaseline(to)

            // 1. Jack and World Lift Logic
            let showJack = (to == .jackPlaced || to == .jackUp || to == .removed || to == .mount || to == .lowered)
            let extendJack = (to == .jackUp || to == .removed || to == .mount)
            let lift: Float = extendJack ? jackLiftH : 0
            jackRoot?.isEnabled = showJack
            if showJack { setJackScissorPose(progress: extendJack ? 1 : 0) }

            if let wg = wheelGroup, let root = contentRoot {
                let worldBase = root.convert(position: [0, 0, 0], to: nil)
                let worldTarget = SIMD3<Float>(worldBase.x, worldBase.y + lift, worldBase.z)
                let localTarget = root.convert(position: worldTarget, from: nil)
                wg.move(to: Transform(translation: localTarget), relativeTo: contentRoot, duration: 0.55, timingFunction: .easeInOut)
            }

            // 2. Wheel Mounting Logic (Forward path)
            if let wg = wheelGroup, to == .mount {
                let newParts = wg.children.filter { $0.name.contains("_new") }
                for e in newParts {
                    e.isEnabled = true
                    var t = e.transform; t.translation.y += tirePullDist; e.transform = t
                    e.move(to: Transform(translation: t.translation - [0, tirePullDist, 0]), relativeTo: wg, duration: tireFlyInDur, timingFunction: .easeInOut)
                }
                try? await Task.sleep(nanoseconds: UInt64(tireFlyInDur * 1_000_000_000))
                if !Task.isCancelled { await seatLugsInSequence() }
            }

            // 3. Sequential Lug Animations (Must happen before tire removal)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await animateLugsToStage(to)

            // 4. Tire Removal Logic (Only triggers AFTER lugs finish loop)
            if to == .removed {
                try? await Task.sleep(nanoseconds: 500_000_000) // Pause for visual clarity after nuts turn red
                if Task.isCancelled { return }

                if let wg = wheelGroup, let root = contentRoot {
                    let oldParts = wg.children.filter { $0.name.contains("_old") }
                    for e in oldParts { 
                        e.isEnabled = true
                        var t = e.transform; t.translation.y = tirePullDist
                        e.move(to: t, relativeTo: wg, duration: tirePullDur, timingFunction: .easeInOut)
                    }

                    // Wait for pull animation + 1s intuitive delay
                    try? await Task.sleep(nanoseconds: UInt64((tirePullDur + 1.0) * 1_000_000_000))
                    if Task.isCancelled { return }
                    
                    // Smoothly slide to grounded dead position (1ft forward)
                    let deadPos = SIMD3<Float>(0.60, 0.30, -treadOuterR + 0.02)
                    let deadRot = simd_quatf(angle: .pi/2, axis: [1,0,0])
                    for e in oldParts {
                        e.move(to: Transform(scale: .one, rotation: deadRot, translation: deadPos), relativeTo: root, duration: 1.0, timingFunction: .easeInOut)
                    }
                    
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled { setOldTireDeadPose(enabled: true) }
                }
            }
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

                // If this lug was already animated in this stage, skip animation to avoid flicker
                if lugsAnimatedInStage.contains(i) {
                    continue
                }
                
                let base   = bases[i]
                let radial = simd_normalize(SIMD3<Float>(base.x, 0, base.z))

                if target == .loosen {
                    lug.transform = Transform(translation: base)
                    setLugMat(lug, matLugBlue) // Start blue for the animation

                    guard let head = lug.findEntity(named: "rr_lug_head") else { continue }
                    await spinHeadCCWHalfTurn(head, parent: lug)
                    if Task.isCancelled { return }

                    lugsAnimatedInStage.insert(i) // Mark as loosened
                    setLugMat(lug, matLugOrange) // Switch color after animation
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    continue
                }
                
                if target == .removed {
                    lug.transform = Transform(translation: base)
                    setLugMat(lug, matLugOrange) // Start orange (loosened) for the removal step

                    if let head = lug.findEntity(named: "rr_lug_head") { await spinHeadCCWHalfTurn(head, parent: lug) }
                    if Task.isCancelled { return }

                    let up = SIMD3<Float>(base.x, base.y + lugFlyDist, base.z)
                    // Move faster (0.25s) as requested
                    lug.move(to: Transform(scale: .one, rotation: simd_quatf(angle: .pi/10, axis: [0, 1, 0]), translation: up), relativeTo: wheelGroup, duration: 0.25, timingFunction: .easeInOut)
                    
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s total for removal
                    if Task.isCancelled { return }

                    lugsAnimatedInStage.insert(i) // Mark as removed
                    setLugMat(lug, matLugRed) // Switch color after removal
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }

                // Default behavior for all other stages (your original logic)
                let (pos, rot, mat) = lugTransform(base: base, radial: radial,
                                                   stage: target, index: i)

                lug.move(to: Transform(scale: .one, rotation: rot, translation: pos),
                         relativeTo: wheelGroup, duration: 0.28,
                         timingFunction: .easeInOut)
                setLugMat(lug, mat)

                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }

        @MainActor
        private func seatLugsInSequence() async {
            let n = sessionModel.expectedLugCount
            let bases = lugPositions(count: n)

            for i in 0..<n {
                if Task.isCancelled { return }
                guard let lug = lugEntities[i], i < bases.count else { continue }

                // Start slightly "out" (along normal) then push in
                let base = bases[i]
                let out  = SIMD3<Float>(base.x, base.y + 0.06, base.z)

                lug.transform.translation = out
                setLugMat(lug, matLugBlue)

                lug.move(to: Transform(scale: .one,
                                       rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                       translation: base),
                         relativeTo: wheelGroup,
                         duration: 0.22,
                         timingFunction: .easeInOut)

                try? await Task.sleep(nanoseconds: 110_000_000)
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
            let hasAnimated = lugsAnimatedInStage.contains(index)
            
            switch stage {
            case .base:
                return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), matLugBlue)

            case .chockPlaced:
                return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), matLugBlue)

            case .loosen:
                return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), hasAnimated ? matLugOrange : matLugBlue)

            case .jackPlaced, .jackUp:
                // Persistent Orange: they stay loosened through jacking
                return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), matLugOrange)

            case .removed:
                if hasAnimated {
                    let up = SIMD3<Float>(base.x, base.y + lugFlyDist, base.z)
                    return (up, simd_quatf(angle: .pi / 10, axis: [0, 1, 0]), matLugRed)
                } else {
                    // Start Orange (loosened) then animate to Red
                    return (base, simd_quatf(angle: 0, axis: [0, 1, 0]), matLugOrange)
                }

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

        private func oldTireParts() -> [Entity] {
            guard let wg = wheelGroup else { return [] }
            return [
                wg.findEntity(named: "rr_tire_old_tread"),
                wg.findEntity(named: "rr_tire_old_inner"),
                wg.findEntity(named: "rr_tire_old_hub"),
            ].compactMap { $0 }
        }

        private func reparentKeepWorld(_ e: Entity, to newParent: Entity) {
            let wp = e.position(relativeTo: nil)
            let wo = e.orientation(relativeTo: nil)
            let ws = e.scale(relativeTo: nil)
            e.removeFromParent()
            newParent.addChild(e)
            e.setPosition(wp, relativeTo: nil)
            e.setOrientation(wo, relativeTo: nil)
            e.setScale(ws, relativeTo: nil)
        }

        private func applyStageBaseline(_ s: Stage) {
            // Do NOT enable dead pose immediately in .removed; we will animate into it later.
            if s != .removed { setOldTireDeadPose(enabled: false) }

            let showSpare = (s == .mount || s == .lowered)
            let showOld = !showSpare
            
            wheelGroup?.findEntity(named: "rr_tire_old_tread")?.isEnabled = showOld
            wheelGroup?.findEntity(named: "rr_tire_old_inner")?.isEnabled = showOld
            wheelGroup?.findEntity(named: "rr_tire_old_hub")?.isEnabled   = showOld

            wheelGroup?.findEntity(named: "rr_tire_new_tread")?.isEnabled = showSpare
            wheelGroup?.findEntity(named: "rr_tire_new_inner")?.isEnabled = showSpare
            wheelGroup?.findEntity(named: "rr_tire_new_hub")?.isEnabled   = showSpare

            let showJack = (s == .jackPlaced || s == .jackUp || s == .removed || s == .mount || s == .lowered)
            jackRoot?.isEnabled = showJack
            jackPointMarker?.isEnabled = showJack

            jackFlashTask?.cancel(); jackFlashTask = nil
            chockFlashTask?.cancel(); chockFlashTask = nil
            
            // Chock visibility: show from Step 4 until the car is lowered
            let showChock = (s == .chockPlaced || s == .loosen || s == .jackPlaced || s == .jackUp || s == .removed || s == .mount)
            chockMarker?.isEnabled = showChock

            if s == .chockPlaced {
                // Step 4: Flash bright yellow
                chockFlashTask = Task { @MainActor in
                    var isGlow = false
                    while !Task.isCancelled {
                        if sessionRunning, var mat = chockMarker?.model?.materials.first as? PhysicallyBasedMaterial {
                            mat.emissiveIntensity = isGlow ? 3.0 : 0.2
                            chockMarker?.model?.materials = [mat]
                        }
                        isGlow.toggle()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            } else if showChock {
                // Step 5+: Solid base yellow
                if var mat = chockMarker?.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.emissiveIntensity = 0.5
                    chockMarker?.model?.materials = [mat]
                }
            }

            if s == .jackPlaced {
                // Step 6: Finding the jack point - Glow Red and Flash
                jackFlashTask = Task { @MainActor in
                    var isGlow = false
                    while !Task.isCancelled {
                        if sessionRunning, var mat = jackPointMarker?.model?.materials.first as? PhysicallyBasedMaterial {
                            mat.emissiveIntensity = isGlow ? 4.0 : 0.2
                            jackPointMarker?.model?.materials = [mat]
                        }
                        isGlow.toggle()
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            } else {
                // Step 7+: Return to steady base red glow
                if var mat = jackPointMarker?.model?.materials.first as? PhysicallyBasedMaterial {
                    mat.emissiveIntensity = 0.8
                    jackPointMarker?.model?.materials = [mat]
                }
            }
        }

        private func setOldTireDeadPose(enabled: Bool) {
            guard let root = contentRoot, let wg = wheelGroup else { return }

            func old(_ n: String) -> Entity? { wg.findEntity(named: n) ?? root.findEntity(named: n) }
            let names = ["rr_tire_old_tread","rr_tire_old_inner","rr_tire_old_hub"]
            let olds = names.compactMap { old($0) }
            guard !olds.isEmpty else { return }

            func reparentKeepWorld(_ e: Entity, to newParent: Entity) {
                let wp = e.position(relativeTo: nil)
                let wo = e.orientation(relativeTo: nil)
                let ws = e.scale(relativeTo: nil)
                e.removeFromParent()
                newParent.addChild(e)
                e.setPosition(wp, relativeTo: nil)
                e.setOrientation(wo, relativeTo: nil)
                e.setScale(ws, relativeTo: nil)
            }

            if enabled {
                if !oldTireIsDetached {
                    for e in olds { reparentKeepWorld(e, to: root) } // detach from wheel lift
                    oldTireIsDetached = true
                }
                for e in olds { e.isEnabled = true }

                // Place 60cm to the side and approx. 1 foot (0.30m) forward toward the user
                let deadLocal = SIMD3<Float>(0.60, 0.30, -treadOuterR + treadHalfW)

                for e in olds {
                    // Flatten tire visually on the floor at the user-facing location
                    e.transform = Transform(scale: .one,
                                            rotation: simd_quatf(angle: .pi/2, axis: [1,0,0]),
                                            translation: deadLocal)
                }
            } else {
                // restore to wheelGroup and restore canonical transforms (teleport OK)
                if oldTireIsDetached {
                    for e in olds { reparentKeepWorld(e, to: wg) }
                    oldTireIsDetached = false
                }

                for n in names {
                    if let e = wg.findEntity(named: n),
                       let t = canonicalTireLocal[n] {
                        e.transform = t
                        e.isEnabled = true
                    }
                }
            }
        }

        private func setLugMat(_ lug: Entity, _ mat: SimpleMaterial) {
            if let head = lug.findEntity(named: "rr_lug_head") as? ModelEntity {
                head.model?.materials = [mat]
                (head.findEntity(named: "rr_lug_tick") as? ModelEntity)?.model?.materials = [mat]
            }
            (lug.findEntity(named: "rr_lug_stem") as? ModelEntity)?.model?.materials = [mat]
        }

        private func spinHeadCCWHalfTurn(_ head: Entity, parent lug: Entity) async {
            head.transform = .identity
            if Task.isCancelled { return }

            // Your current sign is producing CLOCKWISE on-device, so flip it.
            let currentRot = head.transform.rotation
            let halfTurnCCW = simd_quatf(angle: +.pi, axis: [0, 1, 0])  // CCW 180°
            let nextRot = simd_mul(halfTurnCCW, currentRot)

            head.move(to: Transform(scale: .one, rotation: nextRot, translation: .zero),
                      relativeTo: lug,
                      duration: 0.25,
                      timingFunction: .linear)

            try? await Task.sleep(nanoseconds: 250_000_000)

            // keep it clean for later stages
            head.transform = .identity
        }

        private func setArm(_ arm: ModelEntity?, from a: SIMD3<Float>, to b: SIMD3<Float>) {
            guard let arm else { return }
            let v = b - a
            let len = max(0.001, simd_length(v))
            let dir = v / len

            // mesh is length 1 along +X, so scale.x = len
            let rot = simd_quatf(from: SIMD3<Float>(1,0,0), to: dir)
            let mid = (a + b) * 0.5

            arm.transform = Transform(scale: [len, 1, 1], rotation: rot, translation: mid)
        }

        private func setJackScissorPose(progress p: Float) {
            // p: 0 retracted, 1 extended
            guard jackRoot != nil else { return }

            // Choose an arm length that looks right with your base
            let L: Float = 0.18
            // Angle from shallow to steep
            let theta = (Float.pi / 12) + p * (Float.pi / 3) // ~15° -> ~75°

            // Scissor geometry: pivot separation d, height h
            let d = L * cos(theta)   // horizontal distance between opposite pivots
            let h = L * sin(theta)   // scissor height

            // Endpoints (in jackRoot local)
            // base pivots slide in/out; top pivots slide in/out symmetrically
            let leftBase  = SIMD3<Float>(-d/2, 0.010, 0)
            let rightBase = SIMD3<Float>( d/2, 0.010, 0)
            let leftTop   = SIMD3<Float>(-d/2, h,     0)
            let rightTop  = SIMD3<Float>( d/2, h,     0)

            // Top plate and pad follow height
            jackTop?.position = [0, h, 0]
            jackPad?.position = [0, h + 0.015, 0]
            
            jackPointMarker?.position = [0, h + 0.020, 0]

            // Arms CROSS: leftBase->rightTop and rightBase->leftTop
            // front/back arms share same endpoints; Z offset is already in arm.position.z
            let lfA = SIMD3<Float>(leftBase.x,  leftBase.y,  0.020)
            let rtA = SIMD3<Float>(rightTop.x,  rightTop.y,  0.020)
            let rfA = SIMD3<Float>(rightBase.x, rightBase.y, 0.020)
            let ltA = SIMD3<Float>(leftTop.x,   leftTop.y,   0.020)

            let lbA = SIMD3<Float>(leftBase.x,  leftBase.y, -0.020)
            let rtB = SIMD3<Float>(rightTop.x,  rightTop.y, -0.020)
            let rbA = SIMD3<Float>(rightBase.x, rightBase.y,-0.020)
            let ltB = SIMD3<Float>(leftTop.x,   leftTop.y,  -0.020)

            setArm(jackArmLF, from: lfA, to: rtA)
            setArm(jackArmRF, from: rfA, to: ltA)
            setArm(jackArmLB, from: lbA, to: rtB)
            setArm(jackArmRB, from: rbA, to: ltB)
        }

        // ─────────────────────────────────────────────────────────────────────
        // MARK: Reset  (the ONLY path that clears isPlaced)
        // ─────────────────────────────────────────────────────────────────────
        private func resetARSession() {
            guard let arView, let config else { return }

            stageTask?.cancel(); stageTask = nil
            jackFlashTask?.cancel(); jackFlashTask = nil
            chockFlashTask?.cancel(); chockFlashTask = nil

            if let old = wheelARAnchor { arView.session.remove(anchor: old) }
            wheelARAnchor = nil
            
            arView.scene.anchors.removeAll()

            anchorEntity?.removeFromParent()
            anchorEntity = nil; contentRoot = nil; wheelGroup = nil

            tireOldTread = nil; tireOldHub = nil
            tireNewTread = nil; tireNewHub = nil
            jackRoot = nil; jackBase = nil; jackTop = nil; jackPad = nil
            jackArmLF = nil; jackArmRF = nil; jackArmLB = nil; jackArmRB = nil

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
            // replaced lines below as per instruction:
            // for i: UInt32 in 0..<6 { idx += [12, (i+1)%6, i] }
            // for i: UInt32 in 0..<6 { idx += [13, i+6, ((i+1)%6)+6] }

            // bottom cap (visible from -Y)
            for i: UInt32 in 0..<6 { idx += [12, i, (i+1)%6] }
            // top cap (visible from +Y)
            for i: UInt32 in 0..<6 { idx += [13, ((i+1)%6)+6, i+6] }

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
            statusTask?.cancel()
            statusTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.sessionModel.setStatus(nil, phase: .none)
            }
        }
    }
}

