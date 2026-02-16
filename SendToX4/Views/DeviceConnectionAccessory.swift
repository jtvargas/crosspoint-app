import SwiftUI

/// Apple Music-inspired device connection accessory that persists above the tab bar.
///
/// Shows device connection status, firmware/host info, upload progress,
/// and provides connect/disconnect/refresh actions from any tab.
struct DeviceConnectionAccessory: View {
    var deviceVM: DeviceViewModel
    var convertVM: ConvertViewModel
    var settings: DeviceSettings
    var queueCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Upload progress bar — thin line across full width
            if isUploading {
                ProgressView(value: deviceVM.uploadProgress, total: 1.0)
                    .tint(.accentColor)
                    .scaleEffect(y: 0.5)
            }

            HStack(spacing: 12) {
                // Status dot with pulse animation
                statusDot

                // Two-line info
                VStack(alignment: .leading, spacing: 2) {
                    primaryLine
                    secondaryLine
                }

                Spacer()

                // Action buttons
                actionButtons
            }
        }
        .padding()
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .scaleEffect(shouldPulse ? 1.3 : 1.0)
            .opacity(shouldPulse ? 0.6 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: shouldPulse
            )
    }

    // MARK: - Text Lines

    @ViewBuilder
    private var primaryLine: some View {
        if isUploading, let filename = deviceVM.uploadFilename {
            Text(loc(.sendingFilePercent, uploadDisplayName(filename), Int(deviceVM.uploadProgress * 100)))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        } else {
            Text("\(deviceVM.firmwareLabel)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
    }

    private func uploadDisplayName(_ filename: String) -> String {
        let name = filename
            .replacingOccurrences(of: ".epub", with: "")
            .replacingOccurrences(of: ".bmp", with: "")
        return name.truncated(to: 24)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if deviceVM.isSearching {
            Text(loc(.scanningNetwork))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if deviceVM.isConnected {
            Text("\(deviceVM.connectedHost ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if queueCount > 0 {
            Text(loc(.epubsQueued, queueCount))
                .font(.caption)
                .foregroundStyle(AppColor.warning)
        } else {
            Text(loc(.tapConnectToSearch))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if deviceVM.isSearching {
            ProgressView()
                .controlSize(.small)
        } else if isUploading {
            // Replace Disconnect/Refresh with a non-interactive progress capsule
            HStack(spacing: 6) {
                ProgressView(value: deviceVM.uploadProgress, total: 1.0)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.accentColor)

                Text("\(Int(deviceVM.uploadProgress * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        } else {
            HStack(spacing: 8) {
                // Refresh
                Button {
                    Task { await deviceVM.refresh(settings: settings) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

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
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(deviceVM.isConnected ? .secondary : .accentColor)
            }
        }
    }

    // MARK: - Helpers

    private var isUploading: Bool {
        deviceVM.isUploading
            && deviceVM.uploadProgress > 0
            && deviceVM.uploadProgress < 1.0
    }

    private var shouldPulse: Bool {
        deviceVM.isSearching || isUploading
    }

    private var statusColor: Color {
        if deviceVM.isSearching { return AppColor.warning }
        return deviceVM.isConnected ? AppColor.success : AppColor.error
    }
}
