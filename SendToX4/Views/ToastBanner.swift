import SwiftUI

struct ToastBanner: View {
    var message: ToastMessage
    var dismiss: () -> Void

    private var symbol: String {
        switch message.kind {
        case .success: "checkmark.circle.fill"
        case .queued: "tray.and.arrow.down.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch message.kind {
        case .success: AppColor.success
        case .queued: AppColor.warning
        case .error: AppColor.error
        }
    }

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle = message.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.primary.opacity(0.08))
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("toast.\(message.kind)")
    }
}
