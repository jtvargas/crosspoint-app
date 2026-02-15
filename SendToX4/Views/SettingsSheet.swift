import SwiftUI

/// Device configuration sheet with native iOS Settings style.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var deviceVM: DeviceViewModel
    @Bindable var settings: DeviceSettings

    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Device Section

                Section {
                    Picker("Firmware", selection: $settings.firmwareType) {
                        ForEach(FirmwareType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if settings.firmwareType == .custom {
                        TextField("Device IP Address", text: $settings.customIP)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            .textContentType(.none)
                            #endif
                    }

                    LabeledContent("Address", value: settings.resolvedHost)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Device")
                } footer: {
                    Text("CrossPoint uses crosspoint.local (fallback: 192.168.4.1). Stock uses 192.168.3.3.")
                }

                // MARK: - Feature Folders Section

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Convert")
                            .font(.subheadline.weight(.medium))
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            TextField("content", text: $settings.convertFolder)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("WallpaperX")
                            .font(.subheadline.weight(.medium))
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            TextField("sleep", text: $settings.wallpaperFolder)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Feature Folders")
                } footer: {
                    Text("Each feature uploads to its own folder on the device (e.g. /\(settings.convertFolder)/). Tap a field to change the destination.")
                }

                // MARK: - Connection Test

                Section {
                    Button {
                        Task {
                            isTesting = true
                            testResult = nil
                            await deviceVM.refresh(settings: settings)
                            testResult = deviceVM.isConnected
                                ? "Connected (\(deviceVM.firmwareLabel))"
                                : "Not reachable"
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else if let result = testResult {
                                Text(result)
                                    .foregroundStyle(
                                        deviceVM.isConnected ? AppColor.success : AppColor.error
                                    )
                                    .font(.footnote)
                            }
                        }
                    }
                    .disabled(isTesting)
                }

                // MARK: - About Section

                Section {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("EPUB Format", value: "EPUB 2.0")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
