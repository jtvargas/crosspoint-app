import Foundation

// MARK: - Fit Mode

/// How the source image fills the target device canvas.
enum WallpaperFitMode: String, CaseIterable, Sendable {
    case fill    = "Fill"
    case fit     = "Fit"
    case stretch = "Stretch"

    /// SF Symbol for display in segmented controls.
    var iconName: String {
        switch self {
        case .fill:    return "arrow.up.left.and.arrow.down.right"
        case .fit:     return "arrow.down.right.and.arrow.up.left"
        case .stretch: return "arrow.left.and.right"
        }
    }
}

// MARK: - 9-Point Alignment

/// Alignment anchor within the target canvas.
enum WallpaperAlignment: String, CaseIterable, Sendable {
    case topLeft      = "top-left"
    case topCenter    = "top-center"
    case topRight     = "top-right"
    case centerLeft   = "center-left"
    case centerCenter = "center-center"
    case centerRight  = "center-right"
    case bottomLeft   = "bottom-left"
    case bottomCenter = "bottom-center"
    case bottomRight  = "bottom-right"

    /// Grid position (column 0-2, row 0-2) for the alignment grid UI.
    var gridPosition: (column: Int, row: Int) {
        switch self {
        case .topLeft:      return (0, 0)
        case .topCenter:    return (1, 0)
        case .topRight:     return (2, 0)
        case .centerLeft:   return (0, 1)
        case .centerCenter: return (1, 1)
        case .centerRight:  return (2, 1)
        case .bottomLeft:   return (0, 2)
        case .bottomCenter: return (1, 2)
        case .bottomRight:  return (2, 2)
        }
    }

    /// Horizontal component of the alignment.
    var horizontal: HorizontalComponent {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft:       return .left
        case .topCenter, .centerCenter, .bottomCenter: return .center
        case .topRight, .centerRight, .bottomRight:    return .right
        }
    }

    /// Vertical component of the alignment.
    var vertical: VerticalComponent {
        switch self {
        case .topLeft, .topCenter, .topRight:          return .top
        case .centerLeft, .centerCenter, .centerRight: return .center
        case .bottomLeft, .bottomCenter, .bottomRight: return .bottom
        }
    }

    enum HorizontalComponent { case left, center, right }
    enum VerticalComponent { case top, center, bottom }
}

// MARK: - Rotation

/// Image rotation in 90-degree increments.
enum WallpaperRotation: Int, CaseIterable, Sendable {
    case none   = 0
    case cw90   = 90
    case cw180  = 180
    case cw270  = 270

    /// Rotate 90 degrees clockwise.
    var rotatedClockwise: WallpaperRotation {
        WallpaperRotation(rawValue: (rawValue + 90) % 360) ?? .none
    }

    /// Rotate 90 degrees counter-clockwise.
    var rotatedCounterClockwise: WallpaperRotation {
        WallpaperRotation(rawValue: (rawValue - 90 + 360) % 360) ?? .none
    }

    /// Whether width and height are swapped (90 or 270 degrees).
    var swapsDimensions: Bool {
        self == .cw90 || self == .cw270
    }

    /// Rotation angle in radians for Core Graphics transforms.
    var radians: CGFloat {
        CGFloat(rawValue) * .pi / 180.0
    }
}

// MARK: - Color Depth

/// BMP output bit depth.
enum BMPColorDepth: Int, CaseIterable, Sendable {
    case depth24 = 24
    case depth8  = 8
    case depth4  = 4
    case depth1  = 1

    /// Human-readable label.
    var label: String {
        switch self {
        case .depth24: return "24-bit"
        case .depth8:  return "8-bit"
        case .depth4:  return "4-bit"
        case .depth1:  return "1-bit"
        }
    }

    /// Whether this depth is recommended for the X4 device.
    var isRecommended: Bool {
        self == .depth24 || self == .depth8
    }

    /// Warning text for non-recommended depths.
    var warningText: String? {
        isRecommended ? nil : "Not recommended for use with X4"
    }
}

// MARK: - Wallpaper Settings

/// All user-configurable settings for wallpaper conversion.
///
/// This is ephemeral state owned by the ViewModel — not persisted via SwiftData.
/// Defaults match the reference converter's recommended settings for e-ink displays.
struct WallpaperSettings: Sendable {
    var fitMode: WallpaperFitMode = .fill
    var alignment: WallpaperAlignment = .centerCenter
    var rotation: WallpaperRotation = .none
    var colorDepth: BMPColorDepth = .depth24
    var grayscale: Bool = true
    var invert: Bool = false
}
