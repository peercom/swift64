import SwiftUI
import MetalKit
import C64Core
import AVFoundation
import UniformTypeIdentifiers

/// Main content view wrapping the Metal display and handling keyboard/audio.
struct ContentView: View {
    @ObservedObject var emulator: EmulatorController

    var body: some View {
        MetalView(emulator: emulator)
            .aspectRatio(CGSize(width: 403, height: 284), contentMode: .fit)
            .frame(minWidth: 806, minHeight: 568)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                emulator.loadFile(url)
            }
        }
        return true
    }
}

/// Controls the emulator lifecycle: ROM loading, audio, keyboard events.
final class EmulatorController: ObservableObject {
    let c64 = C64()
    var audioEngine: AVAudioEngine?
    var audioSourceNode: AVAudioSourceNode?
    /// Exposed so the debugger bridge can access snapshots.
    weak var renderer: MetalRenderer?

    init() {
        loadROMs()
        c64.powerOn()
        setupAudio()
    }

    /// Load a file by auto-detecting its type from extension.
    func loadFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "d64", "g64":
            if c64.mountDisk(url) {
                print("Disk mounted: \(url.lastPathComponent)")
            }
        case "t64", "tap":
            if c64.mountTape(url) {
                print("Tape mounted: \(url.lastPathComponent)")
            }
        case "prg", "p00":
            c64.loadPRG(url, autoRun: true)
            print("PRG loaded: \(url.lastPathComponent)")
        default:
            // Try to guess: if < 200K, probably PRG; if ~170K, probably D64
            if let data = try? Data(contentsOf: url) {
                if data.count == 174848 || data.count == 175531 {
                    if c64.mountDisk(data) {
                        print("Disk mounted (guessed): \(url.lastPathComponent)")
                    }
                } else if data.count >= 3 {
                    c64.loadPRG(data, autoRun: true)
                    print("PRG loaded (guessed): \(url.lastPathComponent)")
                }
            }
        }
    }

    func loadROMs() {
        // Try Bundle.module first (SPM resource bundle)
        if let romsURL = Bundle.module.url(forResource: "ROMS", withExtension: nil) {
            loadROMsFromDirectory(romsURL)
            return
        }

        // Fallback: look relative to executable and working directory
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execDir.appendingPathComponent("C64_C64App.bundle/Contents/Resources/ROMS"),
            execDir.appendingPathComponent("ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/C64/ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Sources/C64App/ROMS"),
        ]

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.path) {
                loadROMsFromDirectory(dir)
                return
            }
        }

        print("WARNING: Could not find ROM files. The emulator will not boot correctly.")
    }

    func loadROMsFromDirectory(_ dir: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            var basicData: Data?
            var kernalData: Data?
            var charData: Data?

            for file in files {
                let lower = file.lowercased()
                let path = dir.appendingPathComponent(file)
                if lower.contains("basic") {
                    basicData = try Data(contentsOf: path)
                } else if lower.contains("kernal") {
                    kernalData = try Data(contentsOf: path)
                } else if lower.contains("character") || lower.contains("char") {
                    charData = try Data(contentsOf: path)
                }
            }

            if let basic = basicData, let kernal = kernalData, let charset = charData {
                c64.loadROMs(basic: basic, kernal: kernal, charset: charset)
                print("ROMs loaded successfully from \(dir.path)")
            } else {
                print("WARNING: Not all ROM files found in \(dir.path)")
            }
        } catch {
            print("ERROR loading ROMs: \(error)")
        }
    }

    func setupAudio() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let sampleRate = SID.sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let sid = c64.sid

        audioSourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in bufferList {
                let frames = Int(frameCount)
                let ptr = buffer.mData!.bindMemory(to: Float.self, capacity: frames)
                for i in 0..<frames {
                    if sid.sampleReadPos != sid.sampleWritePos {
                        ptr[i] = sid.sampleBuffer[sid.sampleReadPos]
                        sid.sampleReadPos = (sid.sampleReadPos + 1) % sid.sampleBuffer.count
                    } else {
                        ptr[i] = 0
                    }
                }
            }
            return noErr
        }

        if let sourceNode = audioSourceNode {
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
            } catch {
                print("Audio engine failed to start: \(error)")
            }
        }
    }

    deinit {
        audioEngine?.stop()
    }
}

/// NSViewRepresentable wrapper for MTKView.
struct MetalView: NSViewRepresentable {
    let emulator: EmulatorController

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 50  // PAL
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        // Register for drag & drop
        view.registerForDraggedTypes([.fileURL])

        let renderer = MetalRenderer(mtkView: view, c64: emulator.c64)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        emulator.renderer = renderer

        // Set up keyboard event monitoring
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            return context.coordinator.handleKeyEvent(event)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(emulator: emulator)
    }

    class Coordinator {
        let emulator: EmulatorController
        var renderer: MetalRenderer?

        init(emulator: EmulatorController) {
            self.emulator = emulator
        }

        func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
            let c64 = emulator.c64

            switch event.type {
            case .keyDown:
                // Let menu shortcuts through (Cmd+key)
                if event.modifierFlags.contains(.command) {
                    return event
                }

                if !event.isARepeat {
                    if c64.keyboard.isRestoreKey(event.keyCode) {
                        c64.cpu.triggerNMI()
                        return nil
                    }
                    if c64.joystick.handleKeyDown(keyCode: event.keyCode) {
                        return nil
                    }
                    _ = c64.keyboard.handleKeyDown(keyCode: event.keyCode, characters: event.characters)
                }
                return nil

            case .keyUp:
                if event.modifierFlags.contains(.command) {
                    return event
                }
                if c64.joystick.handleKeyUp(keyCode: event.keyCode) {
                    return nil
                }
                _ = c64.keyboard.handleKeyUp(keyCode: event.keyCode, characters: event.characters)
                return nil

            case .flagsChanged:
                handleModifier(keyCode: event.keyCode, flags: event.modifierFlags)
                return nil

            default:
                return event
            }
        }

        func handleModifier(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
            let c64 = emulator.c64

            switch keyCode {
            case 56:
                if flags.contains(.shift) { _ = c64.keyboard.handleKeyDown(keyCode: 56) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 56) }
            case 60:
                if flags.contains(.shift) { _ = c64.keyboard.handleKeyDown(keyCode: 60) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 60) }
            case 59:
                if flags.contains(.control) { _ = c64.keyboard.handleKeyDown(keyCode: 59) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 59) }
            case 58:
                if flags.contains(.option) { _ = c64.keyboard.handleKeyDown(keyCode: 58) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 58) }
            default: break
            }
        }
    }
}
