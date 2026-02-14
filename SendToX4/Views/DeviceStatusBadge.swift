import SwiftUI

/// Glass-styled device connection status indicator.
struct DeviceStatusBadge: View {
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    var body: some View {
        HStack(spacing: 8) {
            // Connection indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            if deviceVM.isSearching {
                ProgressView()
                    .controlSize(.small)
                Text("Searching...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(deviceVM.isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if deviceVM.isConnected {
                    Text("(\(deviceVM.firmwareLabel))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Refresh button
            Button {
                Task {
                    await deviceVM.refresh(settings: settings)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .disabled(deviceVM.isSearching)

            // Settings indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }

    private var statusColor: Color {
        if deviceVM.isSearching { return .orange }
        return deviceVM.isConnected ? .green : .red
    }
}
