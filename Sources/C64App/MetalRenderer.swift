import MetalKit
import C64Core

/// Metal-based renderer that displays the C64 VIC-II framebuffer.
final class MetalRenderer: NSObject, MTKViewDelegate {
    private struct FragmentUniforms {
        var crtEnabled: UInt32
        var intensity: Float
        var sourceWidth: Float
        var sourceHeight: Float
        var horizontalCenterOffset: Float
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    var texture: MTLTexture
    var crtShaderEnabled = false
    var crtShaderIntensity: Float = 0.65

    weak var c64: C64?

    /// Emulation runs on a dedicated thread; these hold the latest completed framebuffer.
    private var frameBuffers: [[UInt32]]
    private var frontBufferIndex = 0
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
    struct FragmentUniforms {
        uint crtEnabled;
        float intensity;
        float sourceWidth;
        float sourceHeight;
        float horizontalCenterOffset;
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
                                    texture2d<float> tex [[texture(0)]],
                                    constant FragmentUniforms &uniforms [[buffer(0)]]) {
        constexpr sampler s(mag_filter::nearest, min_filter::nearest, address::clamp_to_edge);
        float2 presentedCoord = in.texCoord;
        presentedCoord.x = clamp(
            in.texCoord.x - uniforms.horizontalCenterOffset / uniforms.sourceWidth,
            0.0,
            1.0
        );
        float4 color = tex.sample(s, presentedCoord);
        if (uniforms.crtEnabled == 0) {
            return color;
        }

        float2 texel = 1.0 / float2(uniforms.sourceWidth, uniforms.sourceHeight);
        float3 glow = (
            tex.sample(s, presentedCoord + float2(texel.x, 0)).rgb +
            tex.sample(s, presentedCoord - float2(texel.x, 0)).rgb +
            tex.sample(s, presentedCoord + float2(0, texel.y)).rgb +
            tex.sample(s, presentedCoord - float2(0, texel.y)).rgb
        ) * 0.25;

        float intensity = clamp(uniforms.intensity, 0.0, 1.0);
        float scanline = 1.0 - intensity * 0.18 * (0.5 + 0.5 * cos(presentedCoord.y * uniforms.sourceHeight * 6.2831853));
        float maskPhase = fmod(floor(presentedCoord.x * uniforms.sourceWidth * 3.0), 3.0);
        float3 mask = maskPhase < 1.0 ? float3(1.08, 0.96, 0.96) : (maskPhase < 2.0 ? float3(0.96, 1.07, 0.96) : float3(0.96, 0.96, 1.08));
        float2 centered = in.texCoord * 2.0 - 1.0;
        float vignette = 1.0 - intensity * 0.16 * dot(centered, centered);

        color.rgb = mix(color.rgb, glow, intensity * 0.12);
        color.rgb *= scanline * mask * vignette;
        color.rgb = pow(max(color.rgb, 0.0), float3(0.96));
        return float4(clamp(color.rgb, 0.0, 1.0), color.a);
    }
    """

    init?(mtkView: MTKView, c64: C64) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
        mtkView.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.c64 = c64

        let pixelCount = VIC.screenWidth * VIC.screenHeight
        frameBuffers = [
            [UInt32](repeating: 0, count: pixelCount),
            [UInt32](repeating: 0, count: pixelCount),
        ]

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
        stop()
    }

    func configure(for view: MTKView) {
        view.device = device
    }

    func stop() {
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

            // Copy into the back buffer, then publish it with an index swap.
            lock.lock()
            let backBufferIndex = 1 - frontBufferIndex
            lock.unlock()
            frameBuffers[backBufferIndex].withUnsafeMutableBufferPointer { dst in
                c64.vic.framebuffer.withUnsafeBufferPointer { src in
                    if let dstBase = dst.baseAddress, let srcBase = src.baseAddress {
                        dstBase.update(from: srcBase, count: min(dst.count, src.count))
                    }
                }
            }
            lock.lock()
            frontBufferIndex = backBufferIndex
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
            let frameDuration = 1.0 / c64.machineProfile.displayFrameRateHz
            let sleepTime = frameDuration - elapsed
            if sleepTime > 0 {
                Thread.sleep(forTimeInterval: sleepTime)
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Upload the latest completed framebuffer to texture. Keep the lock while
        // Metal copies from the Swift buffer so the emulation thread cannot reuse it.
        lock.lock()
        frameBuffers[frontBufferIndex].withUnsafeBufferPointer { ptr in
            texture.replace(
                region: MTLRegionMake2D(0, 0, VIC.screenWidth, VIC.screenHeight),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: VIC.screenWidth * 4
            )
        }
        lock.unlock()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        var uniforms = FragmentUniforms(
            crtEnabled: crtShaderEnabled ? 1 : 0,
            intensity: crtShaderIntensity,
            sourceWidth: Float(VIC.screenWidth),
            sourceHeight: Float(VIC.screenHeight),
            horizontalCenterOffset: Float(VIC.screenWidth) / 2.0 - Float(VIC.displayLeft + VIC.displayRight) / 2.0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
