import Foundation
import CoreGraphics

/// A deterministic debounce used by the live monitor. Time is supplied by the
/// caller so tests don't need to sleep and changing text always invalidates Use.
public struct TypingPause {
    private var key: String?
    private var changedAt: TimeInterval = 0
    public let delay: TimeInterval
    public init(delay: TimeInterval = 0.65) { self.delay = delay }
    public mutating func ready(key next: String, now: TimeInterval) -> Bool {
        if key != next { key = next; changedAt = now; return false }
        return now - changedAt >= delay
    }
    public mutating func reset() { key = nil }
}

public enum NotchGeometry {
    /// Physical display frame, deliberately not visibleFrame (which starts
    /// below the menu bar). Keeps the island attached to the very top edge.
    public static func expandedFrame(screen: CGRect, width: CGFloat = 600, contentHeight: CGFloat = 240, safeTop: CGFloat, centerX: CGFloat? = nil, backingScale: CGFloat = 2) -> CGRect {
        topPinnedFrame(screen: screen, width: width, height: contentHeight + max(28, safeTop), centerX: centerX, backingScale: backingScale)
    }

    public static func compactFrame(screen: CGRect, notchWidth: CGFloat, safeTop: CGFloat, centerX: CGFloat? = nil, backingScale: CGFloat = 2) -> CGRect {
        topPinnedFrame(screen: screen, width: NotchLayout(notchWidth: notchWidth).bandWidth, height: max(28, safeTop), centerX: centerX, backingScale: backingScale)
    }

    private static func topPinnedFrame(screen: CGRect, width: CGFloat, height: CGFloat, centerX: CGFloat?, backingScale: CGFloat) -> CGRect {
        let scale = max(1, backingScale)
        let w = (min(width, screen.width - 40) * scale).rounded() / scale
        let x = (((centerX ?? screen.midX) - w / 2) * scale).rounded() / scale
        let bottom = ((screen.maxY - height) * scale).rounded(.down) / scale
        // One physical pixel of overscan prevents the top antialiasing seam.
        let top = (screen.maxY * scale).rounded(.up) / scale + 1 / scale
        return CGRect(x: x, y: bottom, width: w, height: top - bottom)
    }
}
