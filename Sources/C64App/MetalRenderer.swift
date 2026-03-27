import MetalKit
import C64Core

/// Metal-based renderer that displays the C64 VIC-II framebuffer.
final class MetalRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    var texture: MTLTexture

    weak var c64: C64?

    /// Emulation runs on a dedicated thread; this holds the latest completed framebuffer.
    var displayBuffer: [UInt32]
    let lock = NSLock()
    var emulationThread: Thread?
    var running = true

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };
    vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
        float2 positions[6] = {
            float2(-1, -1), float2( 1, -1), float2(-1,  1),
            float2(-1,  1), float2( 1, -1), float2( 1,  1)
        };
        float2 texCoords[6] = {
            float2(0, 1), float2(1, 1), float2(0, 0),
            float2(0, 0), float2(1, 1), float2(1, 0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0, 1);
        out.texCoord = texCoords[vertexID];
        return out;
    }
    fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(mag_filter::nearest, min_filter::nearest);
        return tex.sample(s, in.texCoord);
    }
    """

    init?(mtkView: MTKView, c64: C64) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        mtkView.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.c64 = c64

        displayBuffer = [UInt32](repeating: 0, count: VIC.screenWidth * VIC.screenHeight)

        // Create texture
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: VIC.screenWidth,
            height: VIC.screenHeight,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: texDesc) else { return nil }
        self.texture = tex

        // Compile shaders from source
        guard let library = try? device.makeLibrary(source: MetalRenderer.shaderSource, options: nil) else {
            return nil
        }
        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = library.makeFunction(name: "vertexShader")
        pipeDesc.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pipeDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        guard let ps = try? device.makeRenderPipelineState(descriptor: pipeDesc) else { return nil }
        self.pipelineState = ps

        super.init()

        // Start emulation on a dedicated background thread
        startEmulationThread()
    }

    deinit {
        running = false
    }

    func startEmulationThread() {
        let thread = Thread { [weak self] in
            self?.emulationLoop()
        }
        thread.name = "C64 Emulation"
        thread.qualityOfService = .userInteractive
        self.emulationThread = thread
        thread.start()
    }

    /// Latest snapshot for the debugger GUI to read.
    var debugSnapshot: Debugger.Snapshot?
    let snapshotLock = NSLock()

    /// The memory page address the debugger GUI wants to inspect.
    var debugMemoryPage: UInt16 = 0x0000

    func emulationLoop() {
        // PAL: 50 frames per second = 20ms per frame
        let frameDuration: Double = 1.0 / 50.0
        var frameCount = 0

        while running {
            guard let c64 = c64 else { break }

            // If debugger is paused, produce snapshots but don't run
            if c64.debugger.paused {
                snapshotLock.lock()
                debugSnapshot = c64.debugger.takeSnapshot(memoryStart: debugMemoryPage)
                snapshotLock.unlock()
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            let frameStart = CFAbsoluteTimeGetCurrent()

            // Run one C64 frame
            let completed = c64.runFrame()

            // Copy framebuffer for display
            lock.lock()
            displayBuffer = c64.vic.framebuffer
            lock.unlock()

            // Produce debug snapshot every 5 frames (~10 Hz) while running,
            // or immediately when just paused
            frameCount += 1
            if c64.debugger.paused || !completed || frameCount >= 5 {
                frameCount = 0
                snapshotLock.lock()
                debugSnapshot = c64.debugger.takeSnapshot(memoryStart: debugMemoryPage)
                snapshotLock.unlock()
            }

            // Sleep for remaining frame time
            let elapsed = CFAbsoluteTimeGetCurrent() - frameStart
            let sleepTime = frameDuration - elapsed
            if sleepTime > 0 {
                Thread.sleep(forTimeInterval: sleepTime)
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Upload the latest completed framebuffer to texture
        lock.lock()
        let fb = displayBuffer
        lock.unlock()

        fb.withUnsafeBufferPointer { ptr in
            texture.replace(
                region: MTLRegionMake2D(0, 0, VIC.screenWidth, VIC.screenHeight),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: VIC.screenWidth * 4
            )
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
