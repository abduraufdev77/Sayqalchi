import Foundation

/// Two separate, unmodified presses; holding Shift or using Shift in a shortcut
/// must never toggle Yoz. The platform adapter supplies monotonic time.
public struct DoublePress {
    private var down = false
    private var previous: TimeInterval?
    public init() {}
    public mutating func update(pressed: Bool, now: TimeInterval) -> Bool {
        guard pressed != down else { return false }
        down = pressed
        guard pressed else { return false }
        if let previous, now >= previous, now - previous <= 0.45 {
            self.previous = nil
            return true
        }
        previous = now
        return false
    }
    public mutating func cancel() { previous = nil }
}

/// Device-specific modifier bits distinguish Right Shift from Left Shift,
/// including releases while another Shift key remains held.
public struct RightShiftDoublePress {
    private var presses = DoublePress()
    public init() {}
    public mutating func flagsChanged(keyCode: Int64, flags: UInt64, now: TimeInterval) -> Bool {
        let otherModifiers: UInt64 = (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
        guard keyCode == 60, flags & otherModifiers == 0, flags & 0x2 == 0 else {
            presses = DoublePress(); return false
        }
        return presses.update(pressed: flags & 0x4 != 0, now: now)
    }
    public mutating func cancel() { presses.cancel() }
}
