import Foundation
import Metal
import MetalKit
import UIKit

/// Metal-based video renderer for GBA frames
final class VideoRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    // MARK: - Properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?

    // Thread safety for frame buffer updates (double-buffered, owned copy)
    private let bufferLock = NSLock()
    private let frameBuffer: UnsafeMutablePointer<UInt32>
    private var hasNewFrame = false
    private static let bufferSize = Int(GBA_SCREEN_WIDTH) * Int(GBA_SCREEN_HEIGHT)

    // Settings
    var scalingMode: ScalingMode = .fit
    var screenFilter: ScreenFilter = .nearest {
        didSet { updateSamplerState() }
    }

    // MARK: - Vertex Data
    private struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }

    // MARK: - Init

    init?(metalDevice: MTLDevice? = nil) {
        guard let device = metalDevice ?? MTLCreateSystemDefaultDevice() else {
            return nil
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue

        // Create pipeline
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }
        self.pipelineState = pipeline

        // Allocate owned frame buffer (240x160 RGBA = 150KB)
        self.frameBuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: VideoRenderer.bufferSize)
        self.frameBuffer.initialize(repeating: 0, count: VideoRenderer.bufferSize)

        super.init()

        setupTexture()
        setupVertexBuffer()
        updateSamplerState()
    }

    deinit {
        frameBuffer.deallocate()
    }

    // MARK: - Setup

    private func setupTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(GBA_SCREEN_WIDTH),
            height: Int(GBA_SCREEN_HEIGHT),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        texture = device.makeTexture(descriptor: descriptor)
    }

    private func setupVertexBuffer() {
        // Full-screen quad (two triangles)
        let vertices: [Vertex] = [
            Vertex(position: SIMD2(-1, -1), texCoord: SIMD2(0, 1)),
            Vertex(position: SIMD2( 1, -1), texCoord: SIMD2(1, 1)),
            Vertex(position: SIMD2(-1,  1), texCoord: SIMD2(0, 0)),
            Vertex(position: SIMD2( 1,  1), texCoord: SIMD2(1, 0)),
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )
    }

    private func updateSamplerState() {
        let descriptor = MTLSamplerDescriptor()
        switch screenFilter {
        case .nearest:
            descriptor.minFilter = .nearest
            descriptor.magFilter = .nearest
        case .bilinear:
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
        }
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }

    // MARK: - Frame Update (called from emulation thread)

    /// Copies the frame buffer into owned memory (thread-safe)
    func updateFrame(buffer: UnsafePointer<UInt32>) {
        bufferLock.lock()
        // Copy 150KB of pixel data into our owned buffer
        frameBuffer.update(from: buffer, count: VideoRenderer.bufferSize)
        hasNewFrame = true
        bufferLock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }

    func draw(in view: MTKView) {
        // Upload new frame if available
        bufferLock.lock()
        if hasNewFrame {
            texture?.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: Int(GBA_SCREEN_WIDTH), height: Int(GBA_SCREEN_HEIGHT), depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: frameBuffer,
                bytesPerRow: Int(GBA_SCREEN_WIDTH) * 4
            )
            hasNewFrame = false
        }
        bufferLock.unlock()

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Pass viewport info for aspect ratio correction
        var viewportSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        var scaling = Int32(scalingMode == .fit ? 0 : (scalingMode == .fill ? 1 : 2))
        renderEncoder.setVertexBytes(&scaling, length: MemoryLayout<Int32>.size, index: 2)

        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Public

    var metalDevice: MTLDevice { device }

    func configureMTKView(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
}
