import Foundation

/// Angle-driven fold session: closing arms it, full opening ends it.
struct LidMotion {
    private var previousAngle: Double?
    private(set) var isClosing = false
    private(set) var isFoldActive = false

    mutating func reset() {
        previousAngle = nil
        isClosing = false
        isFoldActive = false
    }

    mutating func beginOpening() {
        reset()
        isFoldActive = true
    }

    mutating func update(angle: Double, startAngle: Double = 115) {
        guard angle.isFinite, (0...180).contains(angle) else {
            reset()
            return
        }
        defer { previousAngle = angle }
        if let previousAngle {
            let delta = angle - previousAngle
            if delta < -0.4 {
                isClosing = true
                isFoldActive = true
            }
            if delta > 0.6 { isClosing = false }
        }
        if angle >= startAngle { isFoldActive = false }
    }
}
