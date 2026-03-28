import Foundation
import Emu6502

/// Intercepts C64 Kernal LOAD/SAVE routines and handles them with
/// the virtual disk drive, tape unit, or PRG loader.
///
/// This works by checking the CPU's PC at instruction boundaries.
/// When a trapped address is hit, we perform the operation directly
/// in Swift and return from the Kernal routine via RTS.
public final class KernalTraps {

    // MARK: - Kernal addresses (actual routine entry points, not vectors)

    /// LOAD routine in Kernal ROM. The JMP target of the $FFD5 vector.
    /// On a stock C64 Kernal this is $F49E.
    static let loadRoutine: UInt16 = 0xF49E

    /// SAVE routine entry. JMP target of $FFD8 vector.
    static let saveRoutine: UInt16 = 0xF5DD

    /// OPEN routine entry. JMP target of $FFC0 vector.
    static let openRoutine: UInt16 = 0xF34A

    /// CLOSE routine entry. JMP target of $FFC3 vector.
    static let closeRoutine: UInt16 = 0xF291

    /// CHKIN (set input channel) routine. JMP target of $FFC6.
    static let chkinRoutine: UInt16 = 0xF20E

    /// BASIN/CHRIN routine. JMP target of $FFCF.
    static let basinRoutine: UInt16 = 0xF157

    // MARK: - C64 zero page / Kernal work area locations

    /// File name length
    static let fnLen: UInt16 = 0x00B7
    /// File name pointer (lo/hi)
    static let fnAddr: UInt16 = 0x00BB  // $BB/$BC
    /// Logical file number
    static let logicalFile: UInt16 = 0x00B8
    /// Device number (current)
    static let device: UInt16 = 0x00BA
    /// Secondary address
    static let secondaryAddr: UInt16 = 0x00B9
    /// I/O status word
    static let status: UInt16 = 0x0090
    /// Load/verify flag (0=load, 1=verify)
    static let verifyFlag: UInt16 = 0x0093
    /// End address after load (lo/hi)
    static let endAddrLo: UInt16 = 0x00AE
    static let endAddrHi: UInt16 = 0x00AF
    /// Start address (from LOAD secondary addr)
    static let startAddrLo: UInt16 = 0x00C3
    static let startAddrHi: UInt16 = 0x00C4

    // MARK: - References

    weak var cpu: CPU6502?
    var memory: MemoryMap?
    weak var diskDrive: DiskDrive?
    weak var tapeUnit: TapeUnit?

    /// PRG file queued for immediate loading (drag & drop / menu open)
    public var pendingPRG: PRGLoader.PRGFile?

    /// Whether traps are enabled
    public var enabled: Bool = true

    // MARK: - Init

    public init() {}

    // MARK: - Trap check

    /// Check if the current PC is a trapped Kernal address.
    /// Called at each instruction boundary. Returns true if the trap was handled.
    var debugLogCount = 0

    public func checkTrap() -> Bool {
        guard enabled, let cpu = cpu, let memory = memory else { return false }

        // Debug: sample PC every ~1M cycles to see where CPU is
        debugLogCount += 1
        if debugLogCount % 1000000 == 0 && debugLogCount <= 20000000 {
            debugLog("Sample PC=$\(String(cpu.pc, radix: 16, uppercase: true)) cycle=\(cpu.cycle) pending=\(cpu.pendingCycles) totalCycles=\(cpu.totalCycles)")
        }

        switch cpu.pc {
        case KernalTraps.loadRoutine:
            return handleLoad(cpu: cpu, memory: memory)
        case KernalTraps.saveRoutine:
            return handleSave(cpu: cpu, memory: memory)
        default:
            return false
        }
    }

    func debugLog(_ msg: String) {
        let line = msg + "\n"
        let logPath = "/tmp/c64_debug.log"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    // MARK: - LOAD trap

    func handleLoad(cpu: CPU6502, memory: MemoryMap) -> Bool {
        let deviceNum = memory.ram[Int(KernalTraps.device)]
        let secondaryAddr = memory.ram[Int(KernalTraps.secondaryAddr)]
        let nameLen = memory.ram[Int(KernalTraps.fnLen)]
        let nameLo = memory.ram[Int(KernalTraps.fnAddr)]
        let nameHi = memory.ram[Int(KernalTraps.fnAddr + 1)]
        let nameAddr = UInt16(nameLo) | (UInt16(nameHi) << 8)
        let verifying = cpu.a != 0

        // Read filename from RAM
        var filename = ""
        for i in 0..<Int(nameLen) {
            let ch = memory.ram[Int(nameAddr) + i]
            filename.append(Character(UnicodeScalar(ch)))
        }

        let msg = "[TRAP] LOAD: device=\(deviceNum) secondary=\(secondaryAddr) filename=\"\(filename)\" verify=\(verifying) A=\(cpu.a) mounted=\(diskDrive?.isMounted ?? false)\n"
        if let data = msg.data(using: .utf8) {
            let logPath = "/tmp/c64_debug.log"
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }

        if verifying {
            // VERIFY: just pretend it worked
            setStatus(memory: memory, value: 0)
            doRTS(cpu: cpu, memory: memory)
            return true
        }

        // Print "SEARCHING FOR <filename>" like the real Kernal
        printToScreen(memory: memory, text: "\rSEARCHING FOR \(filename)\r")

        var loadData: [UInt8]? = nil

        switch deviceNum {
        case 1:
            // Tape
            loadData = loadFromTape(filename: filename)

        case 8, 9, 10, 11:
            // Disk
            loadData = loadFromDisk(filename: filename)

        default:
            // Unknown device — let Kernal handle it
            return false
        }

        guard let data = loadData, data.count >= 2 else {
            // File not found
            debugLog("[LOAD] FILE NOT FOUND — loadData=\(loadData == nil ? "nil" : "\(loadData!.count) bytes")")
            setStatus(memory: memory, value: 0x42)  // EOF + file not found
            cpu.a = 4  // FILE NOT FOUND error
            cpu.setFlag(Flags.carry, true)
            doRTS(cpu: cpu, memory: memory)
            return true
        }

        // Print "LOADING" on success
        printToScreen(memory: memory, text: "LOADING\r")

        // First 2 bytes = load address
        let fileLoadAddr = UInt16(data[0]) | (UInt16(data[1]) << 8)

        // Secondary address: 0 = use BASIC start ($0801), 1 = use file address
        let loadAddr: UInt16
        if secondaryAddr == 0 {
            loadAddr = 0x0801  // BASIC start
        } else {
            loadAddr = fileLoadAddr
        }

        // Save the return address from the stack BEFORE writing file data,
        // because the file data may overwrite the stack area ($0100-$01FF).
        let savedRetLo = memory.ram[0x0100 + Int(cpu.sp &+ 1)]
        let savedRetHi = memory.ram[0x0100 + Int(cpu.sp &+ 2)]

        // Copy data to RAM
        let payload = Array(data[2...])
        for (i, byte) in payload.enumerated() {
            let addr = Int(loadAddr) + i
            if addr < 0x10000 {
                memory.ram[addr] = byte
            }
        }

        let endAddr = loadAddr &+ UInt16(payload.count)

        // Restore the return address on the stack (in case file data overwrote it)
        memory.ram[0x0100 + Int(cpu.sp &+ 1)] = savedRetLo
        memory.ram[0x0100 + Int(cpu.sp &+ 2)] = savedRetHi

        debugLog("[LOAD] SUCCESS: \(payload.count) bytes loaded at $\(String(loadAddr, radix: 16, uppercase: true))-$\(String(endAddr - 1, radix: 16, uppercase: true)), endAddr=$\(String(endAddr, radix: 16, uppercase: true))")

        // Set end address pointers
        memory.ram[Int(KernalTraps.endAddrLo)] = UInt8(endAddr & 0xFF)
        memory.ram[Int(KernalTraps.endAddrHi)] = UInt8(endAddr >> 8)

        // Also update BASIC variables pointer if loading to BASIC area
        if loadAddr == 0x0801 || secondaryAddr == 0 {
            // Set start of variables ($2D/$2E) to end of program
            memory.ram[0x2D] = UInt8(endAddr & 0xFF)
            memory.ram[0x2E] = UInt8(endAddr >> 8)
        }

        // Clear status, success
        setStatus(memory: memory, value: 0)
        cpu.a = 0
        cpu.setFlag(Flags.carry, false)

        // Kernal LOAD returns end address in X/Y
        cpu.x = UInt8(endAddr & 0xFF)
        cpu.y = UInt8(endAddr >> 8)

        doRTS(cpu: cpu, memory: memory)
        return true
    }

    // MARK: - SAVE trap

    func handleSave(cpu: CPU6502, memory: MemoryMap) -> Bool {
        // For now, save is not supported — return error
        setStatus(memory: memory, value: 0)
        cpu.a = 0
        cpu.setFlag(Flags.carry, false)
        doRTS(cpu: cpu, memory: memory)
        return true
    }

    // MARK: - Device handlers

    func loadFromDisk(filename: String) -> [UInt8]? {
        guard let drive = diskDrive else {
            debugLog("[DISK] loadFromDisk: diskDrive is nil")
            return nil
        }
        guard drive.isMounted else {
            debugLog("[DISK] loadFromDisk: disk not mounted")
            return nil
        }

        debugLog("[DISK] loadFromDisk: filename=\"\(filename)\" directory has \(drive.directory.count) entries, diskName=\"\(drive.diskName)\"")

        if filename == "$" {
            let listing = drive.generateDirectoryListing()
            debugLog("[DISK] Directory listing: \(listing.count) bytes, first 20: \(listing.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")
            return listing
        }

        guard let entry = drive.findFile(filename) else {
            debugLog("[DISK] File not found: \"\(filename)\" — directory entries: \(drive.directory.map { "\"\($0.filename)\" (\($0.typeName))" }.joined(separator: ", "))")
            return nil
        }

        debugLog("[DISK] Found file: \"\(entry.filename)\" type=\(entry.typeName) track=\(entry.firstTrack) sector=\(entry.firstSector) blocks=\(entry.fileSize)")

        let rawData = drive.readFileData(entry)
        debugLog("[DISK] Read \(rawData.count) bytes. First 10: \(rawData.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))")

        if rawData.count < 2 {
            debugLog("[DISK] WARNING: file data too short (\(rawData.count) bytes), need at least 2 for load address")
        } else {
            let loadAddr = UInt16(rawData[0]) | (UInt16(rawData[1]) << 8)
            debugLog("[DISK] File load address: $\(String(loadAddr, radix: 16, uppercase: true)), payload: \(rawData.count - 2) bytes")
        }

        return rawData
    }

    func loadFromTape(filename: String) -> [UInt8]? {
        guard let tape = tapeUnit, tape.isMounted else { return nil }

        let index: Int
        if let found = tape.findEntry(filename) {
            index = found
        } else {
            return nil
        }

        return tape.readEntry(index)
    }

    // MARK: - Load a pending PRG directly

    /// Called to inject a PRG file directly (from UI action).
    /// This writes the data to RAM and sets up BASIC pointers.
    public func injectPRG(_ prg: PRGLoader.PRGFile, memory: MemoryMap) {
        let endAddr = PRGLoader.load(prg, into: &memory.ram, useFileAddress: true)

        // Update BASIC pointers if loaded to BASIC area
        if prg.loadAddress == 0x0801 {
            memory.ram[0x2D] = UInt8(endAddr & 0xFF)
            memory.ram[0x2E] = UInt8(endAddr >> 8)
        }
    }

    // MARK: - Screen output

    /// Write text directly to C64 screen RAM, advancing the cursor.
    func printToScreen(memory: MemoryMap, text: String) {
        var row = Int(memory.ram[0xD6])
        var col = Int(memory.ram[0xD3])
        let color = memory.ram[0x0286]

        for char in text {
            if char == "\r" {
                col = 0
                row += 1
                if row > 24 {
                    row = 24
                    scrollScreen(memory: memory, color: color)
                }
                continue
            }

            if col < 40 {
                let screenAddr = 0x0400 + row * 40 + col
                memory.ram[screenAddr] = asciiToScreenCode(char)
                memory.colorRAM[row * 40 + col] = color & 0x0F
                col += 1
            }
        }

        memory.ram[0xD3] = UInt8(col)
        memory.ram[0xD6] = UInt8(row)
        let lineStart = 0x0400 + row * 40
        memory.ram[0xD1] = UInt8(lineStart & 0xFF)
        memory.ram[0xD2] = UInt8((lineStart >> 8) & 0xFF)
    }

    /// Scroll the screen up by one line.
    func scrollScreen(memory: MemoryMap, color: UInt8) {
        // Move lines 1-24 up to 0-23
        for row in 0..<24 {
            let dst = 0x0400 + row * 40
            let src = 0x0400 + (row + 1) * 40
            for col in 0..<40 {
                memory.ram[dst + col] = memory.ram[src + col]
                memory.colorRAM[row * 40 + col] = memory.colorRAM[(row + 1) * 40 + col]
            }
        }
        // Clear last line
        let lastLine = 0x0400 + 24 * 40
        for col in 0..<40 {
            memory.ram[lastLine + col] = 0x20  // space
            memory.colorRAM[24 * 40 + col] = color & 0x0F
        }
    }

    /// Convert ASCII/Unicode character to C64 screen code.
    func asciiToScreenCode(_ char: Character) -> UInt8 {
        guard let ascii = char.asciiValue else { return 0x20 }
        switch ascii {
        case 0x20...0x3F: return ascii           // space, digits, punctuation
        case 0x41...0x5A: return ascii - 0x40    // uppercase A-Z → $01-$1A
        case 0x61...0x7A: return ascii - 0x60    // lowercase a-z → $01-$1A
        default: return 0x20                     // space for unknown
        }
    }

    // MARK: - Helpers

    func setStatus(memory: MemoryMap, value: UInt8) {
        memory.ram[Int(KernalTraps.status)] = value
    }

    /// Simulate RTS: pop return address from stack, set PC.
    func doRTS(cpu: CPU6502, memory: MemoryMap) {
        let sp = cpu.sp
        let lo = memory.ram[0x0100 + Int(sp &+ 1)]
        let hi = memory.ram[0x0100 + Int(sp &+ 2)]
        cpu.sp = sp &+ 2
        cpu.pc = (UInt16(hi) << 8 | UInt16(lo)) &+ 1
        // Reset CPU cycle state so it fetches next instruction
        cpu.cycle = 0
        cpu.servicingInterrupt = false
    }
}
