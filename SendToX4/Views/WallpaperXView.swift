import PhotosUI
import StoreKit
import SwiftData
import SwiftUI

// MARK: - WallpaperXView

/// WallpaperX — convert images to BMP format for the X4 e-reader.
///
/// Layout:
/// - **iOS**: Preview fills the screen. Quick controls (rotation) live in the
///   `tabViewBottomAccessory` (set in MainView). Full settings open via a system
///   `.sheet()` with presentation detents — smooth 120fps, no custom gestures.
/// - **macOS**: Inline scroll layout with settings below the preview.
struct WallpaperXView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Bindable var wallpaperVM: WallpaperViewModel
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings

    @State private var showDevicePopover = false
    @State private var showAppSettings = false

    var body: some View {
        NavigationStack {
            #if os(iOS)
            iOSLayout
            #else
            macOSLayout
            #endif
        }
        .onChange(of: wallpaperVM.shouldRequestReview) { _, shouldPrompt in
            if shouldPrompt {
                wallpaperVM.shouldRequestReview = false
                ReviewPromptManager.recordPromptShown()
                requestReview()
            }
        }
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        VStack(spacing: 0) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .navigationTitle(loc(.tabWallpaperX))
        .toolbar { wallpaperToolbar }
        .fileImporter(
            isPresented: $wallpaperVM.showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { handleFileImport($0) }
        .sheet(isPresented: $wallpaperVM.showShareSheet) {
            if let data = wallpaperVM.lastBMPData,
               let filename = wallpaperVM.lastBMPFilename {
                WallpaperShareSheetView(bmpData: data, filename: filename)
            }
        }
        .sheet(isPresented: $showAppSettings) {
            SettingsSheet(deviceVM: deviceVM, settings: settings)
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                devicePreviewCard
                imageSourceButtons

                if wallpaperVM.sourceImage != nil {
                    settingsControls
                        .padding(20)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    statusDisplay
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .navigationTitle(loc(.tabWallpaperX))
        .settingsToolbar(deviceVM: deviceVM, settings: settings)
        .toolbar { toolbarActions }
        .fileImporter(
            isPresented: $wallpaperVM.showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { handleFileImport($0) }
        .sheet(isPresented: $wallpaperVM.showShareSheet) {
            if let data = wallpaperVM.lastBMPData,
               let filename = wallpaperVM.lastBMPFilename {
                WallpaperShareSheetView(bmpData: data, filename: filename)
            }
        }
    }
    #endif

    // MARK: - Preview Area (iOS)

    private var previewArea: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 4)
            devicePreviewCard
            imageSourceButtons
                .padding(.horizontal)
            Spacer(minLength: 4)
        }
    }

    // MARK: - Device Preview Card

    private var devicePreviewCard: some View {
        VStack(spacing: 6) {
            ZStack {
                if let preview = wallpaperVM.processedPreview {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(
                            wallpaperVM.device.aspectRatio,
                            contentMode: .fit
                        )
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .aspectRatio(
                            wallpaperVM.device.aspectRatio,
                            contentMode: .fit
                        )
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.artframe")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text(loc(.selectAnImage))
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.tertiary.opacity(0.5), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.horizontal)

            HStack(spacing: 4) {
                Image(systemName: "display")
                    .font(.caption2)
                Text(wallpaperVM.device.name)
                    .font(.caption2.weight(.medium))
                Text(
                    "\(Int(wallpaperVM.device.resolution.width))\u{00D7}\(Int(wallpaperVM.device.resolution.height))"
                )
                .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Image Source Buttons

    private var imageSourceButtons: some View {
        HStack(spacing: 10) {
            PhotosPicker(
                selection: $wallpaperVM.selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(loc(.photos), systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))

            Button {
                wallpaperVM.showFileImporter = true
            } label: {
                Label(loc(.tabFiles), systemImage: "folder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))

            if wallpaperVM.sourceImage != nil {
                Button(role: .destructive) {
                    wallpaperVM.clearImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Settings Controls (shared between macOS inline & iOS sheet)

    var settingsControls: some View {
        VStack(spacing: 20) {
            // Fit Mode
            VStack(alignment: .leading, spacing: 8) {
                Text(loc(.fit))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Picker(loc(.fitMode), selection: $wallpaperVM.settings.fitMode) {
                    ForEach(WallpaperFitMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Alignment
            if wallpaperVM.settings.fitMode != .stretch {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc(.alignment))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    alignmentGrid
                }
            }

            Divider()

            // Rotation
            HStack {
                Text(loc(.rotate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer()

                rotationControls
            }

            Divider()

            // Color Depth
            VStack(alignment: .leading, spacing: 8) {
                Text(loc(.depth))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Picker(loc(.depth), selection: $wallpaperVM.settings.colorDepth) {
                    ForEach(BMPColorDepth.allCases, id: \.self) { depth in
                        Text(depth.label).tag(depth)
                    }
                }
                .pickerStyle(.segmented)

                if let warning = wallpaperVM.settings.colorDepth.warningText {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColor.warning)
                }
            }

            Divider()

            // Effects
            Toggle(loc(.grayscale), isOn: $wallpaperVM.settings.grayscale)
                .font(.subheadline)

            Toggle(loc(.invert), isOn: $wallpaperVM.settings.invert)
                .font(.subheadline)
        }
    }

    // MARK: - Alignment Grid

    private var alignmentGrid: some View {
        HStack {
            Spacer()
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            let alignment = alignmentFor(column: col, row: row)
                            let isSelected =
                                wallpaperVM.settings.alignment == alignment
                            Button {
                                wallpaperVM.settings.alignment = alignment
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        isSelected
                                            ? AnyShapeStyle(AppColor.accent)
                                            : AnyShapeStyle(.quaternary)
                                    )
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .fill(
                                                isSelected
                                                    ? AnyShapeStyle(.white)
                                                    : AnyShapeStyle(
                                                        .secondary)
                                            )
                                            .frame(width: 6, height: 6)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func alignmentFor(column: Int, row: Int) -> WallpaperAlignment {
        let all: [[WallpaperAlignment]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .centerCenter, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        return all[row][column]
    }

    // MARK: - Rotation Controls

    private var rotationControls: some View {
        HStack(spacing: 10) {
            Button {
                wallpaperVM.settings.rotation =
                    wallpaperVM.settings.rotation.rotatedCounterClockwise
            } label: {
                Image(systemName: "rotate.left")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)

            Text("\(wallpaperVM.settings.rotation.rawValue)\u{00B0}")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28)

            Button {
                wallpaperVM.settings.rotation =
                    wallpaperVM.settings.rotation.rotatedClockwise
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
    }

    // MARK: - iOS Toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    private var wallpaperToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            // Device connection status
            Button {
                showDevicePopover = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(deviceStatusColor)
                        .frame(width: 7, height: 7)
                    Text(
                        deviceVM.isConnected
                            ? loc(.connected) : loc(.notConnected)
                    )
                    .font(.caption2)
                }
            }
            .popover(isPresented: $showDevicePopover) {
                devicePopoverContent
            }

            // Gear (app settings)
            Button {
                showAppSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if wallpaperVM.lastBMPData != nil {
                Button {
                    wallpaperVM.showShareSheet = true
                } label: {
                    Label(loc(.save), systemImage: "square.and.arrow.up")
                }
            }

            Button {
                Task {
                    await wallpaperVM.convertAndSend(
                        deviceVM: deviceVM,
                        settings: settings,
                        modelContext: modelContext
                    )
                }
            } label: {
                if wallpaperVM.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        deviceVM.isConnected ? loc(.sendLabel) : loc(.tabConvert),
                        systemImage: deviceVM.isConnected
                            ? "paperplane.fill" : "photo.artframe"
                    )
                }
            }
            .disabled(
                wallpaperVM.sourceImage == nil || wallpaperVM.isProcessing
                    || deviceVM.isUploading)
        }
    }
    #endif

    // MARK: - Device Popover

    private var devicePopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(deviceStatusColor)
                    .frame(width: 10, height: 10)
                Text(deviceVM.firmwareLabel)
                    .font(.subheadline.weight(.semibold))
            }

            if deviceVM.isConnected, let host = deviceVM.connectedHost {
                Label(host, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    Task { await deviceVM.refresh(settings: settings) }
                } label: {
                    Label(loc(.refresh), systemImage: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    if deviceVM.isConnected {
                        deviceVM.disconnect()
                    } else {
                        Task { await deviceVM.search(settings: settings) }
                    }
                } label: {
                    Text(
                        deviceVM.isConnected ? loc(.disconnect) : loc(.connect)
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(
                    deviceVM.isConnected ? .secondary : .accentColor)
            }

            if deviceVM.isSearching {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loc(.scanning))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }

    // MARK: - macOS Toolbar

    #if os(macOS)
    @ToolbarContentBuilder
    private var toolbarActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if wallpaperVM.lastBMPData != nil {
                Button {
                    wallpaperVM.showShareSheet = true
                } label: {
                    Label(loc(.save), systemImage: "square.and.arrow.up")
                }
            }

            Button {
                Task {
                    await wallpaperVM.convertAndSend(
                        deviceVM: deviceVM,
                        settings: settings,
                        modelContext: modelContext
                    )
                }
            } label: {
                if wallpaperVM.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(
                        deviceVM.isConnected ? loc(.sendLabel) : loc(.tabConvert),
                        systemImage: deviceVM.isConnected
                            ? "paperplane.fill" : "photo.artframe"
                    )
                }
            }
            .disabled(
                wallpaperVM.sourceImage == nil || wallpaperVM.isProcessing
                    || deviceVM.isUploading)
        }
    }
    #endif

    // MARK: - Status Bar (iOS)

    @ViewBuilder
    private var statusBar: some View {
        if let error = wallpaperVM.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.error)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let status = wallpaperVM.statusMessage,
            !wallpaperVM.isProcessing
        {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.success)
                    .font(.caption)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if wallpaperVM.isProcessing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(wallpaperVM.statusMessage ?? loc(.processing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Display (macOS)

    @ViewBuilder
    private var statusDisplay: some View {
        if let error = wallpaperVM.errorMessage {
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
        } else if let status = wallpaperVM.statusMessage,
            !wallpaperVM.isProcessing
        {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.success)
                Text(status)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private var deviceStatusColor: Color {
        if deviceVM.isSearching { return AppColor.warning }
        return deviceVM.isConnected ? AppColor.success : AppColor.error
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                wallpaperVM.loadImage(from: url)
            }
        case .failure(let error):
            wallpaperVM.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WallpaperQuickControls (tab bar bottom accessory)

/// Minimal controls shown in the tab bar bottom accessory when WallpaperX is selected.
/// Contains rotation buttons, an "Advanced" button, and a global upload/batch progress indicator.
struct WallpaperQuickControls: View {
    @Bindable var wallpaperVM: WallpaperViewModel
    var deviceVM: DeviceViewModel
    var queueVM: QueueViewModel
    var rssVM: RSSFeedViewModel
    @Binding var showAdvancedSettings: Bool

    /// True when a single-file upload is actively transferring data.
    private var isUploading: Bool {
        deviceVM.isUploading
    }

    /// True when a multi-item batch operation is running (queue send or RSS batch).
    private var isBatchActive: Bool {
        queueVM.isSending || rssVM.isBatchProcessing
    }

    /// True when any send/upload operation is active.
    private var isBusy: Bool {
        isUploading || isBatchActive
    }

    /// Fractional progress for batch operations (0.0 to 1.0).
    private var batchFraction: Double {
        if let progress = queueVM.sendProgress, progress.total > 0 {
            return Double(progress.current) / Double(progress.total)
        }
        if let progress = rssVM.batchProgress, progress.total > 0 {
            return Double(progress.current) / Double(progress.total)
        }
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar — thin line across full width (matches DeviceConnectionAccessory)
            if isUploading {
                ProgressView(value: deviceVM.uploadProgress, total: 1.0)
                    .tint(.accentColor)
                    .scaleEffect(y: 0.5)
            } else if isBatchActive {
                ProgressView(value: batchFraction, total: 1.0)
                    .tint(.accentColor)
                    .scaleEffect(y: 0.5)
            }

            HStack(spacing: 16) {
                // Rotate CCW
                Button {
                    wallpaperVM.settings.rotation =
                        wallpaperVM.settings.rotation.rotatedCounterClockwise
                } label: {
                    Image(systemName: "rotate.left")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)

                // Rotation label
                Text("\(wallpaperVM.settings.rotation.rawValue)\u{00B0}")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28)

                // Rotate CW
                Button {
                    wallpaperVM.settings.rotation =
                        wallpaperVM.settings.rotation.rotatedClockwise
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)

                Spacer()

                if isUploading {
                    // Show upload progress instead of Advanced button
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(Int(deviceVM.uploadProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else if isBatchActive {
                    // Show batch progress (queue send or RSS batch)
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        if let progress = queueVM.sendProgress ?? rssVM.batchProgress {
                            Text("\(progress.current)/\(progress.total)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else {
                    // Advanced settings button
                    Button {
                        showAdvancedSettings = true
                    } label: {
                        Label(loc(.advanced), systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - WallpaperAdvancedSheet

/// Full settings sheet presented with system detents for smooth 120fps interaction.
#if os(iOS)
struct WallpaperAdvancedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var wallpaperVM: WallpaperViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                // Reuse the shared settings controls from WallpaperXView
                WallpaperXView.settingsControlsContent(wallpaperVM: wallpaperVM)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(loc(.settings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc(.done)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.45), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
#endif

// MARK: - Static settings helper (for sheet reuse)

extension WallpaperXView {
    /// Extracted settings controls as a static function so the sheet can reuse them
    /// without needing a full WallpaperXView instance.
    static func settingsControlsContent(wallpaperVM: WallpaperViewModel)
        -> some View
    {
        _SettingsControlsContent(wallpaperVM: wallpaperVM)
    }
}

/// Internal view wrapping the settings controls for reuse.
private struct _SettingsControlsContent: View {
    @Bindable var wallpaperVM: WallpaperViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Fit Mode
            VStack(alignment: .leading, spacing: 8) {
                Text(loc(.fit))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Picker(loc(.fitMode), selection: $wallpaperVM.settings.fitMode) {
                    ForEach(WallpaperFitMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Alignment
            if wallpaperVM.settings.fitMode != .stretch {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc(.alignment))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    alignmentGrid
                }
            }

            Divider()

            // Rotation
            HStack {
                Text(loc(.rotate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Spacer()

                rotationControls
            }

            Divider()

            // Color Depth
            VStack(alignment: .leading, spacing: 8) {
                Text(loc(.depth))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Picker(
                    loc(.depth), selection: $wallpaperVM.settings.colorDepth
                ) {
                    ForEach(BMPColorDepth.allCases, id: \.self) { depth in
                        Text(depth.label).tag(depth)
                    }
                }
                .pickerStyle(.segmented)

                if let warning = wallpaperVM.settings.colorDepth.warningText
                {
                    Label(
                        warning,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppColor.warning)
                }
            }

            Divider()

            // Effects
            Toggle(loc(.grayscale), isOn: $wallpaperVM.settings.grayscale)
                .font(.subheadline)

            Toggle(loc(.invert), isOn: $wallpaperVM.settings.invert)
                .font(.subheadline)
        }
    }

    // MARK: - Alignment Grid

    private var alignmentGrid: some View {
        HStack {
            Spacer()
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            let alignment = alignmentFor(
                                column: col, row: row)
                            let isSelected =
                                wallpaperVM.settings.alignment == alignment
                            Button {
                                wallpaperVM.settings.alignment = alignment
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        isSelected
                                            ? AnyShapeStyle(AppColor.accent)
                                            : AnyShapeStyle(.quaternary)
                                    )
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .fill(
                                                isSelected
                                                    ? AnyShapeStyle(.white)
                                                    : AnyShapeStyle(
                                                        .secondary)
                                            )
                                            .frame(width: 6, height: 6)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func alignmentFor(column: Int, row: Int) -> WallpaperAlignment {
        let all: [[WallpaperAlignment]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .centerCenter, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]
        return all[row][column]
    }

    // MARK: - Rotation Controls

    private var rotationControls: some View {
        HStack(spacing: 10) {
            Button {
                wallpaperVM.settings.rotation =
                    wallpaperVM.settings.rotation.rotatedCounterClockwise
            } label: {
                Image(systemName: "rotate.left")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)

            Text("\(wallpaperVM.settings.rotation.rawValue)\u{00B0}")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 28)

            Button {
                wallpaperVM.settings.rotation =
                    wallpaperVM.settings.rotation.rotatedClockwise
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
    }
}

// MARK: - Share Sheet (Platform-Adaptive)

#if canImport(UIKit)
import UIKit

struct WallpaperShareSheetView: UIViewControllerRepresentable {
    let bmpData: Data
    let filename: String

    func makeUIViewController(context: Context)
        -> UIActivityViewController
    {
        let tempURL =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try? bmpData.write(to: tempURL)

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

struct WallpaperShareSheetView: NSViewRepresentable {
    let bmpData: Data
    let filename: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let tempURL =
                FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try? bmpData.write(to: tempURL)

            let picker = NSSharingServicePicker(items: [tempURL])
            picker.show(
                relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
