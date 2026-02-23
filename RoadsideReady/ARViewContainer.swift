//
//  Untitled.swift
//  RoadsideReady
//
//  Created by Jason Co on 2/15/26.
//

import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    var currentStepID: String
    @Binding var isAligned: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        switch currentStepID {
        case "ft_loosen":
            context.coordinator.showLugMarkers()
        default:
            context.coordinator.showRingOnly()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isAligned: $isAligned)
    }

    class Coordinator: NSObject {
        var wheelAnchor: AnchorEntity?
        var ringEntity: ModelEntity?

        var arView: ARView?
        @Binding var isAligned: Bool

        init(isAligned: Binding<Bool>) {
            _isAligned = isAligned
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }
            let location = sender.location(in: arView)

            let results = arView.raycast(from: location,
                                         allowing: .existingPlaneGeometry,
                                         alignment: .horizontal)
            guard let first = results.first else { return }

            let anchor = AnchorEntity(world: first.worldTransform)
            self.wheelAnchor = anchor

            let ringMesh = MeshResource.generateCylinder(height: 0.01, radius: 0.15)
            let ringMat = SimpleMaterial(color: .blue, isMetallic: false)
            let ring = ModelEntity(mesh: ringMesh, materials: [ringMat])
            self.ringEntity = ring

            anchor.addChild(ring)
            arView.scene.addAnchor(anchor)

            isAligned = true
        }

        func showRingOnly() {
            guard let anchor = wheelAnchor else { return }
            // Keep ring, remove anything else (lug markers, etc.)
            if let ring = ringEntity {
                anchor.children.removeAll(where: { $0 !== ring })
                if ring.parent == nil { anchor.addChild(ring) }
            } else {
                anchor.children.removeAll()
            }
        }

        func showLugMarkers() {
            guard let anchor = wheelAnchor else { return }

            // Keep ring, clear other children
            if let ring = ringEntity {
                anchor.children.removeAll(where: { $0 !== ring })
                if ring.parent == nil { anchor.addChild(ring) }
            } else {
                anchor.children.removeAll()
            }

            let lugRadius: Float = 0.10
            let lugCount = 5

            for i in 0..<lugCount {
                let angle = Float(i) * (2 * .pi / Float(lugCount))
                let x = lugRadius * cos(angle)
                let z = lugRadius * sin(angle)

                let sphere = MeshResource.generateSphere(radius: 0.015)
                let mat = SimpleMaterial(color: .red, isMetallic: false)
                let lug = ModelEntity(mesh: sphere, materials: [mat])
                lug.position = [x, 0.01, z]
                anchor.addChild(lug)
            }
        }
    }
}
