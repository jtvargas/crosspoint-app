import CoreGraphics
import Testing
@testable import SendToX4

struct DeviceSpecificationTests {

    @Test func x3SpecMatchesPanel() {
        #expect(DeviceSpecification.x3.resolution == CGSize(width: 528, height: 792))
        #expect(DeviceSpecification.all.contains(.x3))
        #expect(DeviceSpecification.all.contains(.x4))
    }

    @Test func wallpaperDeviceAccessorRoundTrips() {
        let settings = DeviceSettings()
        #expect(settings.wallpaperDevice == .x4)

        settings.wallpaperDevice = .x3
        #expect(settings.wallpaperDeviceRaw == "x3")
        #expect(settings.wallpaperDevice == .x3)
    }

    @Test func unknownStoredDeviceFallsBackToX4() {
        let settings = DeviceSettings()
        settings.wallpaperDeviceRaw = "x99"
        #expect(settings.wallpaperDevice == .x4)
    }
}
