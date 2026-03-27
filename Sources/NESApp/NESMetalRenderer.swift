import Foundation
import AppKit
import Metal
import MetalKit
import NESCore

final class NESMetalRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let texture: MTLTexture

    let nes: NES
    var displayBuffer = [UInt8](repeating: 0, count: PPU.screenWidth * PPU.screenHeight * 4)
    let bufferLock = NSLock()

    var emulationThread: Thread?
    var running = false

    init?(mtkView: MTKView, nes: NES) {
        guard let device = mtkView.device,
              let queue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = queue
        self.nes = nes

        // Texture
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: PPU.screenWidth,
            height: PPU.screenHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        self.texture = tex

        // Shaders
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        vertex VertexOut vertexShader(uint vid [[vertex_id]]) {
            float2 positions[6] = {
                float2(-1, -1), float2(1, -1), float2(-1, 1),
                float2(-1, 1), float2(1, -1), float2(1, 1)
            };
            float2 texCoords[6] = {
                float2(0, 1), float2(1, 1), float2(0, 0),
                float2(0, 0), float2(1, 1), float2(1, 0)
            };
            VertexOut out;
            out.position = float4(positions[vid], 0, 1);
            out.texCoord = texCoords[vid];
            return out;
        }
        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(mag_filter::nearest, min_filter::nearest);
            return tex.sample(s, in.texCoord);
        }
        """

        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = library.makeFunction(name: "vertexShader")
        pipeDesc.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pipeDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipeDesc)

        super.init()
        startEmulation()
    }

    func startEmulation() {
        running = true
        emulationThread = Thread {
            while self.running {
                let start = CFAbsoluteTimeGetCurrent()
                _ = self.nes.runFrame()

                self.bufferLock.lock()
                self.displayBuffer = self.nes.ppu.framebuffer
                self.bufferLock.unlock()

                // NTSC: 60 FPS = 16.67ms per frame
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                let remaining = (1.0 / 60.0) - elapsed
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                }
            }
        }
        emulationThread?.qualityOfService = .userInteractive
        emulationThread?.start()
    }

    func stopEmulation() {
        running = false
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        bufferLock.lock()
        let buffer = displayBuffer
        bufferLock.unlock()

        texture.replace(
            region: MTLRegionMake2D(0, 0, PPU.screenWidth, PPU.screenHeight),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: PPU.screenWidth * 4
        )

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}
