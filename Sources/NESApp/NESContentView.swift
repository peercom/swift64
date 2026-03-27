import SwiftUI
import AppKit
import MetalKit
import NESCore

class NESEmulatorController: ObservableObject {
    let nes = NES()

    init() {}
}

struct NESMetalView: NSViewRepresentable {
    let emulator: NESEmulatorController

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.preferredFramesPerSecond = 60
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false

        let renderer = NESMetalRenderer(mtkView: mtkView, nes: emulator.nes)
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer

        // Keyboard events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            return context.coordinator.handleKeyEvent(event)
        }

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(emulator: emulator)
    }

    class Coordinator {
        let emulator: NESEmulatorController
        var renderer: NESMetalRenderer?

        init(emulator: NESEmulatorController) {
            self.emulator = emulator
        }

        func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
            if event.modifierFlags.contains(.command) { return event }
            let nes = emulator.nes

            switch event.type {
            case .keyDown:
                if let btn = mapKey(event.keyCode) {
                    nes.controller1.press(btn)
                    return nil
                }
            case .keyUp:
                if let btn = mapKey(event.keyCode) {
                    nes.controller1.release(btn)
                    return nil
                }
            default:
                break
            }
            return event
        }

        /// Map Mac key codes to NES controller buttons.
        func mapKey(_ keyCode: UInt16) -> UInt8? {
            switch keyCode {
            case 6:   return Controller.Button.a       // Z
            case 7:   return Controller.Button.b       // X
            case 36:  return Controller.Button.start   // Return
            case 56:  return Controller.Button.select  // Left Shift (as select)
            case 49:  return Controller.Button.select  // Space (alt select)
            case 126: return Controller.Button.up      // Up arrow
            case 125: return Controller.Button.down    // Down arrow
            case 123: return Controller.Button.left    // Left arrow
            case 124: return Controller.Button.right   // Right arrow
            // WASD alternative
            case 13:  return Controller.Button.up      // W
            case 1:   return Controller.Button.down    // S
            case 0:   return Controller.Button.left    // A
            case 2:   return Controller.Button.right   // D
            default:  return nil
            }
        }
    }
}

struct NESContentView: View {
    @ObservedObject var emulator: NESEmulatorController

    var body: some View {
        NESMetalView(emulator: emulator)
            .aspectRatio(CGSize(width: 256, height: 240), contentMode: .fit)
            .frame(minWidth: 512, minHeight: 480)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    _ = emulator.nes.loadCartridge(url)
                }
            }
        }
        return true
    }
}
