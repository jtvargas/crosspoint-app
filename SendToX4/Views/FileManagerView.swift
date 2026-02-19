import SwiftUI
import SwiftData
import StoreKit
import UniformTypeIdentifiers

/// Full-featured file manager for browsing and managing files on the X4 device.
struct FileManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    var deviceVM: DeviceViewModel
    var settings: DeviceSettings
    var toast: ToastManager
    @State private var fileVM = FileManagerViewModel()

    // MARK: - Sheet / Dialog State

    @State private var showCreateFolder = false
    @State private var showFileImporter = false
    @State private var itemToDelete: DeviceFile?
    @State private var showDeleteConfirmation = false
    @State private var itemToMove: DeviceFile?
    @State private var itemToRename: DeviceFile?
    @State private var infoDismissed = false

    var body: some View {
        NavigationStack {
            Group {
                if !deviceVM.isConnected {
                    notConnectedView
                } else if fileVM.isLoading && fileVM.files.isEmpty {
                    loadingView
                } else {
                    mainContent
                }
            }
            .navigationTitle(loc(.fileManager))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .settingsToolbar(deviceVM: deviceVM, settings: settings, toast: toast)
            .toolbar {
                // Back / Up button (leading, only when not at root)
                ToolbarItem(placement: .navigation) {
                    if !fileVM.isAtRoot && deviceVM.isConnected {
                        Button {
                            Task { await fileVM.navigateUp() }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }

                // Add menu (new folder / upload)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showCreateFolder = true
                        } label: {
                            Label(loc(.newFolder), systemImage: "folder.badge.plus")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label(loc(.uploadFile), systemImage: "arrow.up.doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!deviceVM.isConnected)
                }

                // Refresh button
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await fileVM.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!deviceVM.isConnected || fileVM.isLoading)
                }
            }
            // MARK: - Sheets & Dialogs
            .sheet(isPresented: $showCreateFolder) {
                CreateFolderSheet { name in
                    await fileVM.createFolder(name: name, modelContext: modelContext)
                }
            }
            // TODO: Re-enable when rename is implemented
            // .sheet(item: $itemToRename) { file in
            //     RenameFileSheet(file: file) { newName in
            //         await fileVM.renameFile(file, to: newName)
            //     }
            // }
            .sheet(item: $itemToMove) { file in
                MoveFileSheet(
                    file: file,
                    fetchFolders: { path in
                        await fileVM.fetchFolders(at: path)
                    },
                    onMove: { destination in
                        await fileVM.moveFile(file, to: destination, modelContext: modelContext)
                    }
                )
            }
            .alert(
                loc(.deleteItemTitle, itemToDelete?.name ?? ""),
                isPresented: $showDeleteConfirmation
            ) {
                Button(loc(.delete), role: .destructive) {
                    if let item = itemToDelete {
                        let contentCount = fileVM.folderContentCount ?? 0
                        Task {
                            if item.isDirectory && contentCount > 0 {
                                _ = await fileVM.deleteItemRecursive(item, totalCount: contentCount, modelContext: modelContext)
                            } else {
                                _ = await fileVM.deleteItem(item, modelContext: modelContext)
                            }
                        }
                    }
                    itemToDelete = nil
                }
                Button(loc(.cancel), role: .cancel) {
                    itemToDelete = nil
                    fileVM.folderContentCount = nil
                }
            } message: {
                if let item = itemToDelete {
                    if item.isDirectory {
                        if let count = fileVM.folderContentCount, count > 0 {
                            Text(loc(.deleteFolderWithContents, count))
                        } else {
                            Text(loc(.deleteFolderMustBeEmpty))
                        }
                    } else {
                        Text(loc(.deleteFilePermanent))
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    .epub,
                    .plainText,
                    UTType(filenameExtension: "xtc") ?? .data,
                    UTType(filenameExtension: "bump") ?? .data,
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            // MARK: - Error Toast
            .onChange(of: fileVM.errorMessage) { _, newError in
                if let error = newError {
                    toast.showError(error)
                    fileVM.errorMessage = nil
                }
            }
            // MARK: - Upload Progress Overlay
            .overlay {
                if deviceVM.isUploading {
                    uploadOverlay
                }
            }
            // MARK: - Delete Progress Overlay
            .overlay {
                if fileVM.isDeleting {
                    deleteOverlay
                }
            }
        }
        .onChange(of: deviceVM.isConnected) {
            fileVM.bind(to: deviceVM.activeService, deviceVM: deviceVM)
            if deviceVM.isConnected {
                Task { await fileVM.refresh() }
            }
        }
        .onChange(of: deviceVM.activeService?.baseURL) {
            fileVM.bind(to: deviceVM.activeService, deviceVM: deviceVM)
        }
        .task {
            fileVM.bind(to: deviceVM.activeService, deviceVM: deviceVM)
            if deviceVM.isConnected {
                await fileVM.refresh()
            }
        }
        .onChange(of: fileVM.shouldRequestReview) { _, shouldPrompt in
            if shouldPrompt {
                fileVM.shouldRequestReview = false
                ReviewPromptManager.recordPromptShown()
                requestReview()
            }
        }
    }

    // MARK: - Main Content (sticky header + list)

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Sticky breadcrumb bar — always visible
            breadcrumbBar
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)

            Divider()

            // Device status bar — sticky below breadcrumbs
            if let status = fileVM.deviceStatus {
                DeviceStatusBar(status: status)
                    .background(.bar)
                Divider()
            }

            // Scrollable file list
            fileListView
        }
    }

    // MARK: - File List

    private var fileListView: some View {
        List {
            // File listing
            if fileVM.files.isEmpty && !fileVM.isLoading {
                Section {
                    ContentUnavailableView {
                        Label(loc(.emptyFolder), systemImage: "folder")
                    } description: {
                        Text(loc(.emptyFolderDescription))
                    }
                    .listRowInsets(EdgeInsets())
                    .frame(minHeight: 200)
                }
            } else {
                Section {
                    ForEach(fileVM.files) { file in
                        if file.isDirectory {
                            Button {
                                Task { await fileVM.navigateTo(file) }
                            } label: {
                                FileManagerRow(
                                    file: file,
                                    supportsMoveRename: fileVM.supportsMoveRename,
                                    onDelete: { prepareDelete(file) },
                                    onMove: nil,
                                    onRename: nil
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            FileManagerRow(
                                file: file,
                                supportsMoveRename: fileVM.supportsMoveRename,
                                onDelete: { prepareDelete(file) },
                                onMove: fileVM.supportsMoveRename ? { itemToMove = file } : nil,
                                onRename: nil // Rename disabled — coming soon
                            )
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text(loc(.itemCount, fileVM.files.count))
                        if !fileVM.files.isEmpty {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            if fileVM.fileCount > 0 {
                                Text(loc(.fileListSummary, fileVM.folderCount, fileVM.fileCount, fileVM.formattedTotalFileSize))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(loc(.fileListSummaryNoFiles, fileVM.folderCount, fileVM.fileCount))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if fileVM.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }

            // Device info note
            if !infoDismissed {
                Section {
                    deviceInfoNote
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .refreshable {
            await fileVM.refresh()
        }
    }

    // MARK: - Breadcrumbs (sticky header)

    private var breadcrumbBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(fileVM.pathComponents.enumerated()), id: \.offset) { index, component in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            Task { await fileVM.navigateToBreadcrumb(component.path) }
                        } label: {
                            if component.name == "/" {
                                Image(systemName: "externaldrive.fill")
                                    .font(.caption)
                            } else {
                                Text(component.name)
                                    .font(.subheadline.weight(
                                        index == fileVM.pathComponents.count - 1 ? .semibold : .regular
                                    ))
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .id(index)
                    }
                }
            }
            .onChange(of: fileVM.currentPath) {
                withAnimation {
                    proxy.scrollTo(fileVM.pathComponents.count - 1, anchor: .trailing)
                }
            }
        }
    }

    // MARK: - Not Connected

    private var notConnectedView: some View {
        ContentUnavailableView {
            Label(loc(.notConnected), systemImage: "wifi.slash")
        } description: {
            Text(loc(.connectToDeviceToManage))
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(loc(.loadingFiles))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Upload Progress Overlay

    private var uploadOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: deviceVM.uploadProgress) {
                    Text(loc(.uploading))
                        .font(.headline)
                } currentValueLabel: {
                    if let name = deviceVM.uploadFilename {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .progressViewStyle(.linear)

                Text("\(Int(deviceVM.uploadProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(40)
        }
    }

    // MARK: - Delete Progress Overlay

    private var deleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let progress = fileVM.deleteProgress {
                    ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                        Text(loc(.deletingProgress, progress.current, progress.total))
                            .font(.headline)
                    } currentValueLabel: {
                        if let name = fileVM.currentDeleteItem {
                            Text(loc(.deletingItem, name))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .progressViewStyle(.linear)

                    Text("\(Int(Double(progress.current) / Double(max(progress.total, 1)) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        fileVM.cancelDelete()
                    } label: {
                        Text(loc(.stopDelete))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColor.error)
                    .disabled(fileVM.deleteCancelled)
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text(loc(.deleteFolderCountingContents))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(40)
        }
    }

    // MARK: - Device Info Note

    private var deviceInfoNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppColor.accent)
                .font(.subheadline)
                .padding(.top, 1)
            Text(loc(.fileManagerDeviceNote))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                withAnimation { infoDismissed = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Prepare Delete

    /// Prepares a delete operation: for folders, counts contents first, then shows confirmation.
    /// For files, shows confirmation immediately.
    private func prepareDelete(_ file: DeviceFile) {
        itemToDelete = file
        fileVM.folderContentCount = nil

        if file.isDirectory {
            // Count contents first, then show confirmation
            Task {
                let count = await fileVM.countFolderContents(file)
                fileVM.folderContentCount = count
                showDeleteConfirmation = true
            }
        } else {
            showDeleteConfirmation = true
        }
    }

    // MARK: - File Import Handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                fileVM.errorMessage = loc(.couldNotAccessFile)
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                Task {
                    await fileVM.uploadFile(data: data, filename: filename, deviceVM: deviceVM, modelContext: modelContext)
                }
            } catch {
                fileVM.errorMessage = loc(.failedToReadFile, error.localizedDescription)
            }

        case .failure(let error):
            fileVM.errorMessage = loc(.fileSelectionFailed, error.localizedDescription)
        }
    }
}
