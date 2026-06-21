import QuickLookThumbnailing
import SceneKit
import GLTFKit2

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let maximumSize = request.maximumSize
        let scale = request.scale

        GLTFAsset.load(with: request.fileURL, options: [:]) { (_, status, maybeAsset, maybeError, _) in
            guard status == .complete, let asset = maybeAsset else {
                if let error = maybeError {
                    handler(nil, error)
                }
                return
            }

            let scene = SCNScene(gltfAsset: asset)

            // Add lighting
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light!.type = .ambient
            ambientLight.light!.intensity = 400
            scene.rootNode.addChildNode(ambientLight)

            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light!.type = .directional
            directionalLight.light!.intensity = 800
            directionalLight.position = SCNVector3(5, 10, 5)
            directionalLight.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(directionalLight)

            // Set up camera
            let cameraNode = self.makeCameraForScene(scene)
            scene.rootNode.addChildNode(cameraNode)

            // Render offscreen
            let pixelWidth = Int(maximumSize.width * scale)
            let pixelHeight = Int(maximumSize.height * scale)

            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            renderer.pointOfView = cameraNode

            let image = renderer.snapshot(
                atTime: 0,
                with: CGSize(width: pixelWidth, height: pixelHeight),
                antialiasingMode: .multisampling4X
            )

            let reply = QLThumbnailReply(contextSize: maximumSize) { context in
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                image.draw(in: CGRect(origin: .zero, size: maximumSize))
                NSGraphicsContext.restoreGraphicsState()
                return true
            }
            handler(reply, nil)
        }
    }

    private func makeCameraForScene(_ scene: SCNScene) -> SCNNode {
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        let fovDegrees: CGFloat = 35
        camera.fieldOfView = fovDegrees
        cameraNode.camera = camera

        guard let (minB, maxB) = worldBounds(scene.rootNode) else {
            cameraNode.position = SCNVector3(2, 1.5, 2)
            cameraNode.look(at: SCNVector3Zero)
            return cameraNode
        }

        let center = SCNVector3((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, (minB.z + maxB.z) / 2)
        let size = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
        let radius = 0.5 * (size.x * size.x + size.y * size.y + size.z * size.z).squareRoot()

        let distance = radius / sin(fovDegrees * .pi / 180 / 2) * 1.05
        let dir = normalize(SCNVector3(0.7, 0.5, 0.7))
        cameraNode.position = SCNVector3(
            center.x + dir.x * distance,
            center.y + dir.y * distance,
            center.z + dir.z * distance
        )
        cameraNode.look(at: center)

        return cameraNode
    }

    // SceneKit's node.boundingBox ignores child-node geometry, so accumulate the
    // bounds of every geometry node transformed into the root's coordinate space.
    private func worldBounds(_ root: SCNNode) -> (SCNVector3, SCNVector3)? {
        let big = CGFloat.greatestFiniteMagnitude
        var minB = SCNVector3(big, big, big)
        var maxB = SCNVector3(-big, -big, -big)
        var found = false

        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (lmin, lmax) = node.boundingBox
            let corners = [
                SCNVector3(lmin.x, lmin.y, lmin.z), SCNVector3(lmax.x, lmin.y, lmin.z),
                SCNVector3(lmin.x, lmax.y, lmin.z), SCNVector3(lmin.x, lmin.y, lmax.z),
                SCNVector3(lmax.x, lmax.y, lmin.z), SCNVector3(lmax.x, lmin.y, lmax.z),
                SCNVector3(lmin.x, lmax.y, lmax.z), SCNVector3(lmax.x, lmax.y, lmax.z),
            ]
            for c in corners {
                let w = root.convertPosition(c, from: node)
                minB = SCNVector3(min(minB.x, w.x), min(minB.y, w.y), min(minB.z, w.z))
                maxB = SCNVector3(max(maxB.x, w.x), max(maxB.y, w.y), max(maxB.z, w.z))
                found = true
            }
        }
        return found ? (minB, maxB) : nil
    }

    private func normalize(_ v: SCNVector3) -> SCNVector3 {
        let len = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        guard len > 0 else { return v }
        return SCNVector3(v.x / len, v.y / len, v.z / len)
    }
}
