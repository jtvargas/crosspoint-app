#if os(macOS)
import SwiftUI

/// Persistent bottom status bar for macOS showing device connection status.
///
/// Similar to Xcode's status bar — a thin horizontal bar at the bottom of the window
/// showing connection state, firmware info, upload progress, and connect/disconnect controls.
struct MacDeviceStatusBar: View {
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Status text
            statusLabel

            Spacer()

            // Upload progress replaces action buttons when active
            if isUploading {
                ProgressView(value: deviceVM.uploadProgress, total: 1.0)
                    .frame(width: 120)
                    .controlSize(.small)

                Text("\(Int(deviceVM.uploadProgress * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            } else {
                // Refresh button
                Button {
                    Task { await deviceVM.refresh(settings: settings) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(deviceVM.isSearching)

                // Connect / Disconnect
                Button {
                    Task {
                        if deviceVM.isConnected {
                            deviceVM.disconnect()
                        } else {
                            await deviceVM.search(settings: settings)
                        }
                    }
                } label: {
                    Text(deviceVM.isConnected ? loc(.disconnect) : loc(.connect))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var statusLabel: some View {
        if deviceVM.isSearching {
            Text(loc(.scanningNetwork))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if deviceVM.isConnected {
            HStack(spacing: 6) {
                Text(deviceVM.firmwareLabel)
                    .font(.caption.weight(.medium))

                if let host = deviceVM.connectedHost {
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(loc(.notConnected))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isUploading: Bool {
        deviceVM.isUploading
            && deviceVM.uploadProgress > 0
            && deviceVM.uploadProgress < 1.0
    }

    private var statusColor: Color {
        if deviceVM.isSearching { return AppColor.warning }
        return deviceVM.isConnected ? AppColor.success : AppColor.error
    }
}
#endif
