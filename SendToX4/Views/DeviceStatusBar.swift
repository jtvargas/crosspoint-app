import SwiftUI

/// Compact device status bar for File Manager header.
struct DeviceStatusBar: View {
    let status: DeviceStatus

    var body: some View {
        HStack(spacing: 12) {
            // IP + Mode
            Label {
                Text(status.ip)
                    .font(.caption.monospaced())
            } icon: {
                Image(systemName: status.mode == "AP" ? "wifi" : "wifi.circle")
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 14)

            // Firmware version
            Text("v\(status.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 14)

            // RSSI signal strength (only in STA mode)
            if status.mode == "STA" {
                Label {
                    Text("\(status.rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: rssiIcon)
                        .foregroundStyle(rssiColor)
                        .font(.caption)
                }

                Divider()
                    .frame(height: 14)
            }

            // Uptime
            Label {
                Text(status.formattedUptime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - RSSI Helpers

    private var rssiIcon: String {
        if status.rssi > -50 { return "wifi" }
        if status.rssi > -70 { return "wifi" }
        return "wifi.exclamationmark"
    }

    private var rssiColor: Color {
        if status.rssi > -50 { return .green }
        if status.rssi > -70 { return .yellow }
        return .red
    }
}
