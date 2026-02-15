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
        if currentStepID == "ft_loosen" {
                context.coordinator.showLugMarkers()
            }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isAligned: $isAligned)
    }

    class Coordinator: NSObject {
        var wheelAnchor: AnchorEntity?

        var arView: ARView?
        @Binding var isAligned: Bool

        init(isAligned: Binding<Bool>) {
            _isAligned = isAligned
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            let location = sender.location(in: arView)

            let results = arView.raycast(from: location,
                                         allowing: .estimatedPlane,
                                         alignment: .horizontal)

            if let first = results.first {

                let anchor = AnchorEntity(world: first.worldTransform)
                self.wheelAnchor = anchor

                let ring = MeshResource.generateCylinder(
                    height: 0.01,
                    radius: 0.15
                )

                let material = SimpleMaterial(color: .blue,
                                              isMetallic: false)

                let entity = ModelEntity(mesh: ring,
                                         materials: [material])

                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)

                isAligned = true
            }
        }
        func showLugMarkers() {
            guard let anchor = wheelAnchor else { return }

            // Remove previous children (avoid stacking)
            anchor.children.removeAll()

            let lugRadius: Float = 0.1
            let lugCount = 5

            for i in 0..<lugCount {
                let angle = Float(i) * (2 * .pi / Float(lugCount))
                let x = lugRadius * cos(angle)
                let z = lugRadius * sin(angle)

                let sphere = MeshResource.generateSphere(radius: 0.015)
                let material = SimpleMaterial(color: .red, isMetallic: false)
                let lug = ModelEntity(mesh: sphere, materials: [material])

                lug.position = [x, 0.01, z]
                anchor.addChild(lug)
            }
        }

    }
}
