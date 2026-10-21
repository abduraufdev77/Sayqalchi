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
