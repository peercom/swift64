import Foundation
import GameController
import C64Core

/// Routes connected game controllers to the C64 joystick ports.
///
/// The first controller follows the joystick routing preference, exactly like
/// the keyboard joystick. A second controller takes the other port. D-pad and
/// left stick move; A, B, and the shoulder buttons fire.
final class GamepadInputManager {
    private let joystick: Joystick
    private var observers: [NSObjectProtocol] = []
    private(set) var controllers: [GCController] = []

    /// Port assignment for the first controller.
    var routing: JoystickRouting = .both {
        didSet { if routing != oldValue { reapplyAll() } }
    }

    /// Called on the main queue whenever the connected set changes.
    var onControllersChanged: (([String]) -> Void)?

    var controllerNames: [String] {
        controllers.map { $0.vendorName ?? "Game Controller" }
    }

    init(joystick: Joystick) {
        self.joystick = joystick
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.attach(controller)
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.detach(controller)
        })
        for controller in GCController.controllers() {
            attach(controller)
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func attach(_ controller: GCController) {
        guard !controllers.contains(where: { $0 === controller }) else { return }
        controllers.append(controller)
        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] gamepad, _ in
            guard let self, let controller else { return }
            self.apply(gamepad, from: controller)
        }
        controller.microGamepad?.valueChangedHandler = { [weak self, weak controller] gamepad, _ in
            guard let self, let controller else { return }
            self.apply(micro: gamepad, from: controller)
        }
        onControllersChanged?(controllerNames)
    }

    private func detach(_ controller: GCController) {
        guard let index = controllers.firstIndex(where: { $0 === controller }) else { return }
        controllers.remove(at: index)
        controller.extendedGamepad?.valueChangedHandler = nil
        controller.microGamepad?.valueChangedHandler = nil
        // Release everything, then let the remaining controllers reassert.
        joystick.externalPort1 = 0xFF
        joystick.externalPort2 = 0xFF
        reapplyAll()
        onControllersChanged?(controllerNames)
    }

    private func reapplyAll() {
        joystick.externalPort1 = 0xFF
        joystick.externalPort2 = 0xFF
        for controller in controllers {
            if let gamepad = controller.extendedGamepad {
                apply(gamepad, from: controller)
            } else if let gamepad = controller.microGamepad {
                apply(micro: gamepad, from: controller)
            }
        }
    }

    private func apply(_ gamepad: GCExtendedGamepad, from controller: GCController) {
        let dpad = gamepad.dpad
        let stick = gamepad.leftThumbstick
        var bits: UInt8 = 0
        if dpad.up.isPressed || stick.yAxis.value > 0.5 { bits |= 0x01 }
        if dpad.down.isPressed || stick.yAxis.value < -0.5 { bits |= 0x02 }
        if dpad.left.isPressed || stick.xAxis.value < -0.5 { bits |= 0x04 }
        if dpad.right.isPressed || stick.xAxis.value > 0.5 { bits |= 0x08 }
        if gamepad.buttonA.isPressed || gamepad.buttonB.isPressed
            || gamepad.leftShoulder.isPressed || gamepad.rightShoulder.isPressed {
            bits |= 0x10
        }
        write(bits, from: controller)
    }

    private func apply(micro gamepad: GCMicroGamepad, from controller: GCController) {
        let dpad = gamepad.dpad
        var bits: UInt8 = 0
        if dpad.up.isPressed { bits |= 0x01 }
        if dpad.down.isPressed { bits |= 0x02 }
        if dpad.left.isPressed { bits |= 0x04 }
        if dpad.right.isPressed { bits |= 0x08 }
        if gamepad.buttonA.isPressed || gamepad.buttonX.isPressed { bits |= 0x10 }
        write(bits, from: controller)
    }

    /// Active-high `bits` become the active-low port value.
    private func write(_ bits: UInt8, from controller: GCController) {
        guard let index = controllers.firstIndex(where: { $0 === controller }) else { return }
        let value: UInt8 = ~bits & 0x1F | 0xE0
        switch (index, routing) {
        case (0, .both):
            joystick.externalPort1 = value
            joystick.externalPort2 = value
        case (0, .port2), (1, .port1):
            joystick.externalPort2 = value
        case (0, .port1), (1, .both), (1, .port2):
            joystick.externalPort1 = value
        default:
            break
        }
    }
}
