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
    @State private var fileVM = FileManagerViewModel()

    // MARK: - Sheet / Dialog State

    @State private var showCreateFolder = false
    @State private var showFileImporter = false
    @State private var itemToDelete: DeviceFile?
    @State private var itemToMove: DeviceFile?
    @State private var itemToRename: DeviceFile?

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
            .settingsToolbar(deviceVM: deviceVM, settings: settings)
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
                isPresented: Binding(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                )
            ) {
                Button(loc(.delete), role: .destructive) {
                    if let item = itemToDelete {
                        Task { _ = await fileVM.deleteItem(item, modelContext: modelContext) }
                    }
                    itemToDelete = nil
                }
                Button(loc(.cancel), role: .cancel) {
                    itemToDelete = nil
                }
            } message: {
                if let item = itemToDelete {
                    Text(item.isDirectory
                         ? loc(.deleteFolderMustBeEmpty)
                         : loc(.deleteFilePermanent))
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
            // MARK: - Error Banner
            .overlay(alignment: .bottom) {
                if let error = fileVM.errorMessage {
                    errorBanner(error)
                }
            }
            // MARK: - Upload Progress Overlay
            .overlay {
                if deviceVM.isUploading {
                    uploadOverlay
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
                                    onDelete: { itemToDelete = file },
                                    onMove: nil,
                                    onRename: nil
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            FileManagerRow(
                                file: file,
                                supportsMoveRename: fileVM.supportsMoveRename,
                                onDelete: { itemToDelete = file },
                                onMove: fileVM.supportsMoveRename ? { itemToMove = file } : nil,
                                onRename: nil // Rename disabled — coming soon
                            )
                        }
                    }
                } header: {
                    HStack {
                        Text(loc(.itemCount, fileVM.files.count))
                        Spacer()
                        if fileVM.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
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

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.warning)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation { fileVM.errorMessage = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: fileVM.errorMessage)
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
