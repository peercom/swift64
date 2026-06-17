import Foundation

/// IEC serial bus connecting the C64 to the 1541 disk drive.
///
/// Three open-collector lines: ATN, CLK, DATA.
/// Each line is HIGH (true) when nobody pulls it low, and LOW (false) when
/// any participant pulls it low (wired-AND / open-collector).
///
/// Based on VirtualC64's SerialPort implementation.
public final class IECBus {

    // MARK: - Per-device output contributions

    /// C64 outputs (from CIA2 port A)
    public var c64Atn: Bool = false   // true = pulling ATN low
    public var c64Clk: Bool = false   // true = pulling CLK low
    public var c64Data: Bool = false  // true = pulling DATA low

    /// Drive outputs (from VIA1 port B)
    public var driveClk: Bool = false   // PB3: true = pulling CLK low
    public var driveData: Bool = false  // PB1: true = pulling DATA low
    public var driveAtn: Bool = false   // PB4: ATNA output (for XOR gate)

    // MARK: - Combined bus lines (active-high: true = released/high)

    /// ATN line. Only driven by C64.
    public var atnLine: Bool { !c64Atn }

    /// CLK line. Wired-AND of all CLK outputs.
    public var clockLine: Bool { !c64Clk && !driveClk }

    /// DATA line. Wired-AND of all DATA outputs, PLUS the ATN auto-ack XOR gate.
    /// The XOR gate: when atnLine == driveAtn, DATA is pulled low.
    public var dataLine: Bool {
        let baseData = !c64Data && !driveData
        // XOR gate: pulls DATA low when atnLine and driveAtn are the SAME
        // (atnLine XOR driveAtn) = 1 means they differ → no pull
        // (atnLine XOR driveAtn) = 0 means they match → pull DATA low
        let xorGate = atnLine != driveAtn  // true when they differ (no pull)
        return baseData && xorGate
    }

    // MARK: - C64 reads (for CIA2 port A bits 6-7)
    // The C64 serial bus inputs (PA6, PA7) do NOT go through an inverter.
    // Bus LOW (asserted/false) -> CIA reads 0.
    // Bus HIGH (released/true) -> CIA reads 1.

    /// CLK IN for C64 (CIA2 PA bit 6): 0 when CLK line is LOW, $40 when HIGH
    public var c64ReadClk: UInt8 { clockLine ? 0x40 : 0x00 }

    /// DATA IN for C64 (CIA2 PA bit 7): 0 when DATA line is LOW, $80 when HIGH
    public var c64ReadData: UInt8 { dataLine ? 0x80 : 0x00 }

    // MARK: - Drive reads (for VIA1 port B)
    // The 1541 inverts the bus signals on input: line LOW → pin HIGH (1)
    // This matches VICE's ^0x85 inversion on bits 0, 2, 7

    /// Port B input byte for VIA1 (bits 0, 2, 7 from bus; 5-6 device address)
    public var drivePortBInput: UInt8 {
        var pb: UInt8 = 0x00
        // Bit 0: DATA IN (inverted: bus low → 1, bus high → 0)
        if !dataLine { pb |= 0x01 }
        // Bit 2: CLK IN (inverted: bus low → 1, bus high → 0)
        if !clockLine { pb |= 0x04 }
        // Bits 5-6: Device address jumpers. The 1541 ROM rotates these bits
        // into the command address; both low maps to device 8.
        // Bit 7: ATN IN (inverted: bus low → 1, bus high → 0)
        if !atnLine { pb |= 0x80 }
        return pb
    }

    // MARK: - Update from C64 side

    /// Called when CIA2 port A is written.
    public var onBusUpdate: (() -> Void)?

    private var busLog = 0
    /// Update bus from CIA2 port A. Only output-configured pins (DDR=1) can
    /// pull bus lines low. Input pins (DDR=0) float high and don't drive the bus.
    public func updateFromC64(_ portA: UInt8, ddra: UInt8) {
        let driven = portA & ddra  // Only output bits affect the bus
        let oldAtn = c64Atn, oldClk = c64Clk, oldData = c64Data
        c64Atn = driven & 0x08 != 0
        c64Clk = driven & 0x10 != 0
        c64Data = driven & 0x20 != 0
        onBusUpdate?()
        if (c64Atn != oldAtn || c64Clk != oldClk || c64Data != oldData) && busLog < 500 {
            busLog += 1
            iecLog("[IEC-C64] PA=$\(h8(portA)) DDRA=$\(h8(ddra)) c64Atn=\(c64Atn) c64Clk=\(c64Clk) c64Data=\(c64Data) → bus ATN=\(atnLine) CLK=\(clockLine) DATA=\(dataLine) [drvClk=\(driveClk) drvData=\(driveData) drvAtn=\(driveAtn) xor=\(atnLine != driveAtn)]")
        }
    }

    // MARK: - Update from drive side

    /// Called when drive VIA1 port B is written.
    /// Reads the driven output bits (portB & ddrb).
    private var drvLog = 0
    public func updateFromDrive(portB: UInt8, ddrb: UInt8) {
        let driven = portB & ddrb
        let newData = driven & 0x02 != 0
        let newClk = driven & 0x08 != 0
        let newAtn = driven & 0x10 != 0
        if (newData != driveData || newClk != driveClk || newAtn != driveAtn) && drvLog < 500 {
            drvLog += 1
            iecLog("[IEC-DRV] PB=$\(h8(portB)) DDRB=$\(h8(ddrb)) drvData=\(newData) drvClk=\(newClk) drvAtn=\(newAtn) → bus ATN=\(atnLine) CLK=\(!c64Clk && !newClk) DATA=\(!c64Data && !newData && (atnLine != newAtn))")
        }
        driveData = newData
        driveClk = newClk
        driveAtn = newAtn
        onBusUpdate?()
    }

    // MARK: - ATN edge detection for VIA1 CA1

    /// Check for ATN transitions. The 1541 has an inverter on the ATN line
    /// before CA1, so CA1 sees the INVERTED ATN: ATN low → CA1 high.
    /// Returns the current CA1 pin state (inverted ATN).
    public var ca1State: Bool { !atnLine }

    public struct Snapshot: Equatable {
        public let atnLine: Bool
        public let clockLine: Bool
        public let dataLine: Bool
        public let c64Atn: Bool
        public let c64Clock: Bool
        public let c64Data: Bool
        public let driveClock: Bool
        public let driveData: Bool
        public let driveAtn: Bool
    }

    public var snapshot: Snapshot {
        Snapshot(
            atnLine: atnLine,
            clockLine: clockLine,
            dataLine: dataLine,
            c64Atn: c64Atn,
            c64Clock: c64Clk,
            c64Data: c64Data,
            driveClock: driveClk,
            driveData: driveData,
            driveAtn: driveAtn
        )
    }

    // MARK: - Init

    public init() {}

    // MARK: - Debug logging

    private func h8(_ v: UInt8) -> String { String(format: "%02X", v) }

    func iecLog(_ msg: String) {
        C64Trace.log(.iec, msg)
    }
}
