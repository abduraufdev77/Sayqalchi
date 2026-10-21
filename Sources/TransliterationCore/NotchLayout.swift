import CoreGraphics

/// One coordinate system for the persistent band and the result body. Expansion
/// adds an even number of points so AppKit rounding cannot shift their center.
public struct NotchLayout {
    public static let earWidth: CGFloat = 66
    public static let horizontalPadding: CGFloat = 24
    public static let resultGrowth: CGFloat = 22
    public static let logoSize = CGSize(width: 18, height: 18)
    public static let waveformSize = CGSize(width: 33, height: 18)
    public let notchWidth: CGFloat
    public init(notchWidth: CGFloat) { self.notchWidth = max(150, notchWidth) }
    public var bandWidth: CGFloat { notchWidth + Self.earWidth * 2 }
    public var resultWidth: CGFloat { bandWidth + Self.resultGrowth }
    public var contentWidth: CGFloat { bandWidth - Self.horizontalPadding * 2 }
    public var earContentWidth: CGFloat { Self.earWidth - Self.horizontalPadding }
    public func bodyInset(in width: CGFloat) -> CGFloat { (width - contentWidth) / 2 }
    public func bandFrame(in panel: CGRect, bandHeight: CGFloat) -> CGRect {
        CGRect(x: panel.midX - bandWidth / 2, y: panel.maxY - bandHeight, width: bandWidth, height: bandHeight)
    }
    public func logoFrame(in panel: CGRect, bandHeight: CGFloat) -> CGRect {
        let band = bandFrame(in: panel, bandHeight: bandHeight)
        return CGRect(x: band.minX + Self.horizontalPadding, y: band.midY - Self.logoSize.height / 2,
                      width: Self.logoSize.width, height: Self.logoSize.height)
    }
    public func waveformFrame(in panel: CGRect, bandHeight: CGFloat) -> CGRect {
        let band = bandFrame(in: panel, bandHeight: bandHeight)
        return CGRect(x: band.maxX - Self.horizontalPadding - Self.waveformSize.width,
                      y: band.midY - Self.waveformSize.height / 2,
                      width: Self.waveformSize.width, height: Self.waveformSize.height)
    }
}
