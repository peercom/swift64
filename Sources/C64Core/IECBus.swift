import Foundation

/// IEC serial bus connecting the C64 to the 1541 disk drive.
///
/// Three open-collector lines: ATN, CLK, DATA.
/// Open-collector means: any device pulling low wins. The line is high
/// only when nobody drives it low.
public final class IECBus {

    // MARK: - C64 side outputs (from CIA2 port A)

    /// C64 pulls ATN low (CIA2 PA3, active: bit set = pull low)
    public var c64Atn: Bool = false
    /// C64 pulls CLK low (CIA2 PA4)
    public var c64Clk: Bool = false
    /// C64 pulls DATA low (CIA2 PA5)
    public var c64Data: Bool = false

    // MARK: - Drive side outputs (from VIA1 port B)

    /// Drive pulls CLK low (VIA1 PB3)
    public var driveClk: Bool = false
    /// Drive pulls DATA low (VIA1 PB1)
    public var driveData: Bool = false

    /// Drive's ATN acknowledge latch — hardware auto-asserts DATA when ATN goes low.
    /// Cleared by the drive firmware.
    public var driveAtnAck: Bool = false

    // MARK: - Effective bus state (active-low: true = line is HIGH/released)

    /// ATN line state (true = high/released, false = asserted low)
    public var atn: Bool { !c64Atn }

    /// CLK line state
    public var clk: Bool { !c64Clk && !driveClk }

    /// DATA line state
    public var data: Bool { !c64Data && !driveData && !driveAtnAck }

    // MARK: - C64 reads (for CIA2 port A bits 6-7)

    /// CLK IN as seen by C64 (CIA2 PA6, active low: 0 when CLK is low)
    public var c64ClkIn: Bool { !clk }

    /// DATA IN as seen by C64 (CIA2 PA7, active low: 0 when DATA is low)
    public var c64DataIn: Bool { !data }

    // MARK: - Drive reads (for VIA1 port B)

    /// DATA IN as seen by drive (VIA1 PB0, active low: 1 when DATA is low)
    public var driveDataIn: Bool { !data }

    /// CLK IN as seen by drive (VIA1 PB2, active low: 1 when CLK is low)
    public var driveClkIn: Bool { !clk }

    /// ATN IN as seen by drive (VIA1 PB7, active low: 1 when ATN is low)
    public var driveAtnIn: Bool { !atn }

    // MARK: - ATN edge detection

    private var prevAtn: Bool = true  // Previous ATN state (starts high)

    /// Called to check for ATN transitions. Returns true on falling edge.
    public func checkAtnEdge() -> Bool {
        let currentAtn = atn
        let fallingEdge = prevAtn && !currentAtn  // ATN went from high to low
        prevAtn = currentAtn
        return fallingEdge
    }

    // MARK: - Update from C64 side

    /// Debug: log ATN transitions
    private var loggedAtnTransitions = 0

    /// Update bus from CIA2 port A write.
    /// CIA2 PA3=ATN, PA4=CLK, PA5=DATA (active: writing 1 = pulling line low)
    public func updateFromC64(_ portA: UInt8) {
        let prevAtnOut = c64Atn
        c64Atn = portA & 0x08 != 0
        c64Clk = portA & 0x10 != 0
        c64Data = portA & 0x20 != 0

        // ATN acknowledge is handled by XOR logic in Drive1541.updateBusFromVIA1()
        // (ATN_IN XOR PB4). No automatic latch needed here.

        if c64Atn != prevAtnOut && loggedAtnTransitions < 30 {
            loggedAtnTransitions += 1
            let msg = "[IEC] C64 ATN \(c64Atn ? "ASSERT" : "RELEASE") PA=$\(String(format:"%02X", portA)) → bus: ATN=\(atn) CLK=\(clk) DATA=\(data) atnAck=\(driveAtnAck) drvData=\(driveData) drvClk=\(driveClk)\n"
            if let data = msg.data(using: .utf8),
               let fh = FileHandle(forWritingAtPath: "/tmp/c64_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        }
    }

    // MARK: - Update from drive side

    /// Update bus from VIA1 port B write.
    /// VIA1 PB1=DATA OUT, PB3=CLK OUT
    public func updateFromDrive(_ portB: UInt8) {
        driveData = portB & 0x02 != 0
        driveClk = portB & 0x08 != 0
    }

    // MARK: - Init

    public init() {}
}
