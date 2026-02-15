import Foundation

/// Data-driven device profile for wallpaper conversion.
///
/// Each specification describes a target device's screen resolution.
/// New devices are added by creating a new static property and including
/// it in the ``all`` array — no code changes elsewhere required.
nonisolated struct DeviceSpecification: Identifiable, Sendable {
    let id: String
    let name: String
    let resolution: CGSize

    /// Width-to-height ratio of the device screen.
    var aspectRatio: CGFloat {
        resolution.width / resolution.height
    }
}

// MARK: - Equatable & Hashable (CGSize is not Hashable)

extension DeviceSpecification: Equatable {
    static func == (lhs: DeviceSpecification, rhs: DeviceSpecification) -> Bool {
        lhs.id == rhs.id
    }
}

extension DeviceSpecification: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Known Devices

    /// Xtreink X4 e-reader (480 x 800 e-ink display).
    static let x4 = DeviceSpecification(
        id: "x4",
        name: "Xtreink X4",
        resolution: CGSize(width: 480, height: 800)
    )

    /// All known device profiles.
    static let all: [DeviceSpecification] = [.x4]
}
