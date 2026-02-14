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
                            .keyboardType(.decimalPad)
                            .textContentType(.none)
                    }

                    LabeledContent("Address", value: settings.resolvedHost)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Device")
                } footer: {
                    Text("CrossPoint uses crosspoint.local (fallback: 192.168.4.1). Stock uses 192.168.3.3.")
                }

                // MARK: - Storage Section

                Section {
                    TextField("Target Folder", text: $settings.targetFolder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("EPUBs will be saved to /\(settings.targetFolder)/ on the device.")
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
                                        deviceVM.isConnected ? .green : .red
                                    )
                                    .font(.footnote)
                            }
                        }
                    }
                    .disabled(isTesting)
                }

                // MARK: - Experimental Section

                Section {
                    Toggle("WallpaperX", isOn: $settings.showWallpaperX)
                    Toggle("File Manager", isOn: $settings.showFileManager)
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Enable experimental features still in development. WallpaperX allows custom wallpapers on the X4. File Manager lets you browse and manage files on the device.")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
