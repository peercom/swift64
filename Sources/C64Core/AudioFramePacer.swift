/// Wall-clock pacing with bounded recovery of the speaker queue after a late
/// frame. Catch-up runs normal emulated cycles; it never retunes the SID clock.
public struct AudioFramePacer {
    private var deadline: Double

    public init(now: Double) { deadline = now }

    public mutating func reset(now: Double) { deadline = now }

    public mutating func delay(now: Double, frameDuration: Double,
                               bufferedSamples: Int, targetSamples: Int,
                               playbackStarted: Bool) -> Double {
        deadline += frameDuration
        if deadline < now - frameDuration * 2 {
            deadline = now
        }
        if playbackStarted && bufferedSamples < targetSamples {
            // A permanently depleted queue otherwise underruns on every small
            // scheduling fluctuation even after the producer has recovered.
            deadline = now
        }
        return max(0, deadline - now)
    }
}
