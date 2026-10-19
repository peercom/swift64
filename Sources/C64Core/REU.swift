import Foundation
import Emu6502

/// Commodore RAM Expansion Unit (1700/1764/1750 and larger clones) built
/// around the 8726 REC DMA controller, mapped at IO2 ($DF00-$DF1F, mirrored
/// through $DFFF).
///
/// Behaviour follows the REC programming reference and the public REU test
/// programs: the trigger write pulls /DMA at once, so a CPU write in the
/// following cycle is lost; transfers pause while VIC BA is low; stash,
/// fetch and verify move one byte per cycle and swap takes two (its read half
/// runs through BA warning cycles, its write half waits for BA); REU accesses
/// bypass the 6510 port at $0000/$0001 but otherwise see the CPU's banking.
public final class REU {
    public enum Model: String, CaseIterable, Codable, Equatable {
        case reu1700
        case reu1764
        case reu1750
        case reu1MB
        case reu2MB
        case reu4MB
        case reu8MB
        case reu16MB

        public var displayName: String {
            switch self {
            case .reu1700: return "1700 (128 KB)"
            case .reu1764: return "1764 (256 KB)"
            case .reu1750: return "1750 (512 KB)"
            case .reu1MB: return "1 MB"
            case .reu2MB: return "2 MB"
            case .reu4MB: return "4 MB"
            case .reu8MB: return "8 MB"
            case .reu16MB: return "16 MB"
            }
        }

        public var ramSize: Int {
            switch self {
            case .reu1700: return 128 * 1024
            case .reu1764: return 256 * 1024
            case .reu1750: return 512 * 1024
            case .reu1MB: return 1024 * 1024
            case .reu2MB: return 2 * 1024 * 1024
            case .reu4MB: return 4 * 1024 * 1024
            case .reu8MB: return 8 * 1024 * 1024
            case .reu16MB: return 16 * 1024 * 1024
            }
        }

        /// Status register bit 4: set for the 256K-chip units and larger.
        var sizeBitSet: Bool { self != .reu1700 }

        /// Bank register bits that select memory; the rest read as 1.
        var bankBits: Int {
            switch self {
            case .reu1700, .reu1764, .reu1750: return 3
            case .reu1MB: return 4
            case .reu2MB: return 5
            case .reu4MB: return 6
            case .reu8MB: return 7
            case .reu16MB: return 8
            }
        }
    }

    enum TransferType: UInt8 {
        case stash = 0   // C64 -> REU
        case fetch = 1   // REU -> C64
        case swap = 2
        case verify = 3
    }

    public private(set) var model: Model
    public var ram: [UInt8]

    // MARK: - Registers

    /// $DF00 flags: bit 7 interrupt pending, bit 6 end of block, bit 5 fault.
    var statusFlags: UInt8 = 0
    /// $DF01 as last written, with bits 7 and 4 updated by the controller.
    var command: UInt8 = 0x10
    var c64Address: UInt16 = 0
    var c64AddressLatch: UInt16 = 0
    var reuAddress: UInt32 = 0
    var reuAddressLatch: UInt32 = 0
    var length: UInt16 = 0xFFFF
    var lengthLatch: UInt16 = 0xFFFF
    /// $DF09 bits 7 (enable), 6 (end of block), 5 (verify error).
    var interruptMask: UInt8 = 0
    /// $DF0A bits 7 (fix C64 address), 6 (fix REU address).
    var addressControl: UInt8 = 0

    // MARK: - DMA state

    /// The controller owns the bus from the cycle after the trigger write.
    public private(set) var dmaActive = false
    /// Armed by an EXECUTE write with the FF00 bit clear; a write to $FF00 starts it.
    public private(set) var waitingForFF00 = false
    var bytesRemaining = 0
    /// Set once the controller has made its first access of a transfer. The
    /// REC takes the bus only while BA is high; after that only a swap's
    /// write half waits for BA (`reutiming2` g4 transfer starts).
    var holdsBus = false
    var swapReadDone = false
    var swapC64Byte: UInt8 = 0
    var swapREUByte: UInt8 = 0
    /// Last byte driven on the unit's internal data bus. Reads from an
    /// unpopulated bank return it (`floatingbus`: a write of 0 to a missing
    /// bank reads back 0; a valid write first reads back that value).
    var lastDataBusByte: UInt8 = 0xFF
    /// Transfers performed since reset, for diagnostics and tests.
    public private(set) var completedTransferCount: UInt64 = 0
    public private(set) var dmaCycleCount: UInt64 = 0

    /// Fires when the interrupt line changes.
    public var onInterrupt: ((Bool) -> Void)?

    public var interruptActive: Bool { statusFlags & 0x80 != 0 }

    public init(model: Model) {
        self.model = model
        ram = REU.powerOnPattern(size: model.ramSize)
    }

    /// Uninitialised DRAM pattern observed by the public `raminitpattern`
    /// probe: $FF,$00,$00,$FF repeating, inverted in alternate 128K halves.
    static func powerOnPattern(size: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        for index in 0..<size {
            let base: UInt8 = (index & 3 == 0 || index & 3 == 3) ? 0xFF : 0x00
            bytes[index] = (index / 0x20000) & 1 == 0 ? base : ~base
        }
        return bytes
    }

    /// A reset keeps RAM, as a real unit does across a C64 reset.
    public func reset() {
        let wasActive = interruptActive
        statusFlags = 0
        command = 0x10
        c64Address = 0; c64AddressLatch = 0
        reuAddress = 0; reuAddressLatch = 0
        length = 0xFFFF; lengthLatch = 0xFFFF
        interruptMask = 0
        addressControl = 0
        dmaActive = false
        waitingForFF00 = false
        bytesRemaining = 0
        holdsBus = false
        swapReadDone = false
        if wasActive { onInterrupt?(false) }
    }

    // MARK: - Register access

    public func readRegister(_ register: Int) -> UInt8 {
        switch register & 0x1F {
        case 0x00:
            let value = statusFlags | (model.sizeBitSet ? 0x10 : 0x00)
            let wasActive = interruptActive
            statusFlags = 0
            if wasActive { onInterrupt?(false) }
            return value
        case 0x01: return command
        case 0x02: return UInt8(c64Address & 0xFF)
        case 0x03: return UInt8(c64Address >> 8)
        case 0x04: return UInt8(reuAddress & 0xFF)
        case 0x05: return UInt8((reuAddress >> 8) & 0xFF)
        case 0x06:
            let unusedBits: UInt8 = model.bankBits >= 8 ? 0 : UInt8(truncatingIfNeeded: 0xFF << model.bankBits)
            return UInt8((reuAddress >> 16) & 0xFF) | unusedBits
        case 0x07: return UInt8(length & 0xFF)
        case 0x08: return UInt8(length >> 8)
        case 0x09: return interruptMask | 0x1F
        case 0x0A: return addressControl | 0x3F
        default: return 0xFF
        }
    }

    /// Reads without side effects, for the debugger.
    public func debugRegisterValue(_ register: Int) -> UInt8 {
        if register & 0x1F == 0x00 { return statusFlags | (model.sizeBitSet ? 0x10 : 0x00) }
        return readRegister(register)
    }

    public func writeRegister(_ register: Int, value: UInt8) {
        switch register & 0x1F {
        case 0x00:
            break
        case 0x01:
            command = value
            if value & 0x80 != 0 {
                if value & 0x10 != 0 {
                    beginTransfer()
                } else {
                    waitingForFF00 = true
                }
            } else {
                waitingForFF00 = false
            }
        case 0x02:
            c64AddressLatch = (c64AddressLatch & 0xFF00) | UInt16(value)
            c64Address = c64AddressLatch
        case 0x03:
            c64AddressLatch = (c64AddressLatch & 0x00FF) | (UInt16(value) << 8)
            c64Address = c64AddressLatch
        case 0x04:
            reuAddressLatch = (reuAddressLatch & 0xFFFF00) | UInt32(value)
            reuAddress = reuAddressLatch
        case 0x05:
            reuAddressLatch = (reuAddressLatch & 0xFF00FF) | (UInt32(value) << 8)
            reuAddress = reuAddressLatch
        case 0x06:
            reuAddressLatch = (reuAddressLatch & 0x00FFFF) | (UInt32(value) << 16)
            reuAddress = reuAddressLatch
        case 0x07:
            lengthLatch = (lengthLatch & 0xFF00) | UInt16(value)
            length = lengthLatch
        case 0x08:
            lengthLatch = (lengthLatch & 0x00FF) | (UInt16(value) << 8)
            length = lengthLatch
        case 0x09:
            interruptMask = value & 0xE0
            checkInterrupt()
        case 0x0A:
            addressControl = value & 0xC0
        default:
            break
        }
    }

    /// Any write to $FF00 starts an armed transfer. The 6510's own dummy
    /// write in a read-modify-write instruction counts (`rmw-trigger`).
    public func writeFF00() {
        guard waitingForFF00 else { return }
        waitingForFF00 = false
        beginTransfer()
    }

    private func beginTransfer() {
        waitingForFF00 = false
        bytesRemaining = length == 0 ? 0x10000 : Int(length)
        swapReadDone = false
        holdsBus = false
        dmaActive = true
    }

    // MARK: - DMA

    var transferType: TransferType { TransferType(rawValue: command & 0x03)! }
    var fixC64Address: Bool { addressControl & 0x80 != 0 }
    var fixREUAddress: Bool { addressControl & 0x40 != 0 }

    private func ramIndex(_ address: UInt32) -> Int? {
        let masked = Int(address & 0xFFFFFF)
        switch model {
        case .reu1764:
            // Banks 4-7 are not populated on a 256K unit and read as floating bus.
            return masked & 0x40000 != 0 ? nil : masked & (model.ramSize - 1)
        default:
            return masked & (model.ramSize - 1)
        }
    }

    /// An unpopulated bank reads the floating data bus: the last byte the
    /// unit drove or latched. Charge decay over time is not modelled.
    func readREUByte(_ address: UInt32) -> UInt8 {
        guard let index = ramIndex(address) else { return lastDataBusByte }
        lastDataBusByte = ram[index]
        return lastDataBusByte
    }

    func writeREUByte(_ address: UInt32, _ value: UInt8) {
        lastDataBusByte = value
        guard let index = ramIndex(address) else { return }
        ram[index] = value
    }

    /// One phi2 cycle while the controller holds /DMA.
    ///
    /// `busGranted` is AEC high (the VIC is not fetching); `baLow` is BA as
    /// the REC samples it at the start of the cycle; `ioReadsDeselected` is
    /// BA as the PLA sees it, which turns an I/O read into a RAM read.
    ///
    /// Calibrated on the `reutiming2` hardware references: a byte-completing
    /// cycle (stash, fetch, verify, the write half of a swap) needs BA high,
    /// while the read half of a swap only needs the bus and runs through the
    /// BA warning cycles. A write half blocked by BA leaves the byte pending
    /// and the controller reads it again in the next granted cycle, so a
    /// swap resumes after a VIC fetch with whichever half is due; the write
    /// half of the final byte is not held back (f3/g3 transfer ends).
    public func performDMACycle(bus: MemoryMap, busGranted: Bool = true, baLow: Bool = false,
                                ioReadsDeselected: Bool = false) {
        guard dmaActive, busGranted else { return }
        if !holdsBus {
            guard !baLow else { return }
            holdsBus = true
        }
        if transferType == .swap {
            if !swapReadDone {
                dmaCycleCount += 1
                swapC64Byte = bus.dmaRead(c64Address, ioDeselected: ioReadsDeselected)
                swapREUByte = readREUByte(reuAddress)
                swapReadDone = true
            } else if baLow && bytesRemaining > 1 {
                // Not the last byte: the write half waits for BA and the
                // byte is read again first. The final write goes ahead and
                // the transfer ends inside the warning cycles.
                swapReadDone = false
            } else {
                dmaCycleCount += 1
                bus.dmaWrite(c64Address, value: swapREUByte)
                writeREUByte(reuAddress, swapC64Byte)
                swapReadDone = false
                advanceAddresses()
                completeByte()
            }
            return
        }
        guard !baLow else { return }
        dmaCycleCount += 1
        switch transferType {
        case .stash:
            let byte = bus.dmaRead(c64Address, ioDeselected: ioReadsDeselected)
            writeREUByte(reuAddress, byte)
            advanceAddresses()
            completeByte()
        case .fetch:
            let byte = readREUByte(reuAddress)
            bus.dmaWrite(c64Address, value: byte)
            advanceAddresses()
            completeByte()
        case .swap:
            break
        case .verify:
            let c64Byte = bus.dmaRead(c64Address, ioDeselected: ioReadsDeselected)
            let reuByte = readREUByte(reuAddress)
            advanceAddresses()
            if c64Byte != reuByte {
                // `twoblocks` dumps: a fault stops after the mismatching byte
                // with the addresses past it; the length counter holds the
                // rest but never drops below 1, and END OF BLOCK is set once
                // that counter has reached 1 (a fault on either of the last
                // two bytes reads $70, earlier faults $30).
                statusFlags |= 0x20
                bytesRemaining -= 1
                length = UInt16(truncatingIfNeeded: max(1, bytesRemaining))
                finishTransfer(completed: bytesRemaining <= 1, keepLength: true)
            } else {
                completeByte()
            }
        }
    }

    private func advanceAddresses() {
        if !fixC64Address { c64Address &+= 1 }
        if !fixREUAddress { reuAddress = (reuAddress &+ 1) & 0xFFFFFF }
    }

    private func completeByte() {
        bytesRemaining -= 1
        if bytesRemaining > 0 {
            if length > 1 { length -= 1 }
        } else {
            finishTransfer(completed: true)
        }
    }

    /// Final counter state follows the REC: the length register ends at 1 and
    /// the addresses point past the last byte unless fixed; autoload reloads
    /// all three from their latches. EXECUTE clears and the FF00 bit sets.
    private func finishTransfer(completed: Bool, keepLength: Bool = false) {
        dmaActive = false
        bytesRemaining = 0
        swapReadDone = false
        holdsBus = false
        if !keepLength { length = 1 }
        if command & 0x20 != 0 {
            c64Address = c64AddressLatch
            reuAddress = reuAddressLatch
            length = lengthLatch
        }
        command = (command & 0x7F) | 0x10
        if completed { statusFlags |= 0x40 }
        completedTransferCount += 1
        checkInterrupt()
    }

    private func checkInterrupt() {
        let wasActive = interruptActive
        let enabled = interruptMask & 0x80 != 0
        let endOfBlock = statusFlags & 0x40 != 0 && interruptMask & 0x40 != 0
        let fault = statusFlags & 0x20 != 0 && interruptMask & 0x20 != 0
        if enabled && (endOfBlock || fault) {
            statusFlags |= 0x80
        }
        if interruptActive != wasActive { onInterrupt?(interruptActive) }
    }
}

// MARK: - Snapshot state

extension REU {
    public static let snapshotStoredPropertyCount = 23

    func saveState(to w: inout StateWriter) {
        w.write(model.rawValue); w.write(ram)
        w.write(statusFlags); w.write(command)
        w.write(c64Address); w.write(c64AddressLatch); w.write(reuAddress); w.write(reuAddressLatch)
        w.write(length); w.write(lengthLatch); w.write(interruptMask); w.write(addressControl)
        w.write(dmaActive); w.write(waitingForFF00); w.write(bytesRemaining); w.write(holdsBus)
        w.write(swapReadDone); w.write(swapC64Byte); w.write(swapREUByte)
        w.write(lastDataBusByte); w.write(completedTransferCount); w.write(dmaCycleCount)
    }

    func restoreState(from r: inout StateReader) throws {
        guard let savedModel = Model(rawValue: try r.read()) else { throw MachineStateError.invalidValue("REU model") }
        model = savedModel
        ram = try snapshotFixed(try r.read(), count: savedModel.ramSize, "REU RAM")
        statusFlags = try r.read(); command = try r.read()
        c64Address = try r.read(); c64AddressLatch = try r.read(); reuAddress = try r.read(); reuAddressLatch = try r.read()
        length = try r.read(); lengthLatch = try r.read(); interruptMask = try r.read(); addressControl = try r.read()
        dmaActive = try r.read(); waitingForFF00 = try r.read(); bytesRemaining = try r.read(); holdsBus = try r.read()
        swapReadDone = try r.read(); swapC64Byte = try r.read(); swapREUByte = try r.read()
        lastDataBusByte = try r.read(); completedTransferCount = try r.read(); dmaCycleCount = try r.read()
    }
}
