import SwiftUI
import MetalKit

/// SwiftUI wrapper for MTKView to display emulated GBA frames
struct MetalView: UIViewRepresentable {
    let renderer: VideoRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.metalDevice)
        renderer.configureMTKView(view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Settings updates are handled by renderer directly
    }
}
