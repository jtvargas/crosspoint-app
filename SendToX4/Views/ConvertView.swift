import SwiftUI
import SwiftData

/// Main conversion view — URL input, device status, and send button.
struct ConvertView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var convertVM: ConvertViewModel
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    @State private var showShareSheet = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // URL Input Card
                    urlInputCard

                    // Action Buttons
                    actionButtons

                    // Status / Error Display
                    statusDisplay

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("SendToX4")
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
            .sheet(isPresented: $showShareSheet) {
                if let data = convertVM.lastEPUBData,
                   let filename = convertVM.lastFilename {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(filename)
                    ShareSheetView(items: [tempURL], epubData: data, filename: filename)
                }
            }
        }
    }

    // MARK: - URL Input Card

    private var urlInputCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Enter webpage URL", text: $convertVM.urlString)
                    #if os(iOS)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    #endif
                    .autocorrectionDisabled()
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        if !convertVM.isProcessing {
                            Task {
                                await convertVM.convertAndSend(
                                    modelContext: modelContext,
                                    deviceVM: deviceVM,
                                    settings: settings
                                )
                            }
                        }
                    }

                if !convertVM.urlString.isEmpty {
                    Button {
                        convertVM.urlString = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                PasteButton(payloadType: String.self) { strings in
                    if let url = strings.first {
                        convertVM.urlString = url
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            }
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary: Convert & Send
            Button {
                isURLFieldFocused = false
                Task {
                    await convertVM.convertAndSend(
                        modelContext: modelContext,
                        deviceVM: deviceVM,
                        settings: settings
                    )
                }
            } label: {
                HStack {
                    if convertVM.isProcessing {
                        if convertVM.currentPhase == .sending && deviceVM.uploadProgress > 0 {
                            // Determinate progress during upload
                            ProgressView(value: deviceVM.uploadProgress)
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text("Sending \(Int(deviceVM.uploadProgress * 100))%")
                        } else {
                            ProgressView()
                                .tint(.white)
                            Text(convertVM.phaseLabel)
                        }
                    } else {
                        Image(systemName: deviceVM.isConnected
                              ? "paperplane.fill" : "doc.text")
                        Text(deviceVM.isConnected
                             ? "Convert & Send" : "Convert to EPUB")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(
                convertVM.urlString
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || convertVM.isProcessing
            )

            // Secondary: Save to Files
            if convertVM.lastEPUBData != nil {
                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Save to Files")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }
        }
    }

    // MARK: - Status Display

    @ViewBuilder
    private var statusDisplay: some View {
        if let error = convertVM.lastError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.error)
                Text(error)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else if !convertVM.statusMessage.isEmpty {
            HStack {
                Image(systemName: convertVM.currentPhase == .sent
                      ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(convertVM.currentPhase == .sent
                                    ? AppColor.success : AppColor.accent)
                Text(convertVM.statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }
}

// MARK: - Share Sheet

#if canImport(UIKit)
import UIKit

/// UIActivityViewController wrapper for sharing EPUB files on iOS/iPadOS.
struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]
    let epubData: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try? epubData.write(to: tempURL)

        return UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

#elseif canImport(AppKit)
import AppKit

/// NSSharingServicePicker wrapper for sharing EPUB files on macOS.
struct ShareSheetView: NSViewRepresentable {
    let items: [Any]
    let epubData: Data
    let filename: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Trigger the share picker after the view appears
        DispatchQueue.main.async {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try? epubData.write(to: tempURL)

            let picker = NSSharingServicePicker(items: [tempURL])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
