import SwiftUI

/// Sheet for renaming a file on the device.
/// The file extension is locked — only the stem (base name) is editable.
struct RenameFileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let file: DeviceFile
    var onRename: (String) async -> Bool

    @State private var stem: String
    @State private var validationError: String?
    @State private var isRenaming = false

    /// The file extension including the dot (e.g. ".epub"), or empty for folders / extensionless files.
    private let fileExtension: String

    /// The original stem for comparison (disable Rename when unchanged).
    private let originalStem: String

    init(file: DeviceFile, onRename: @escaping (String) async -> Bool) {
        self.file = file
        self.onRename = onRename

        // Split name into stem + extension
        let name = file.name
        if !file.isDirectory, let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex {
            let ext = String(name[dotIndex...])         // ".epub"
            let stemPart = String(name[..<dotIndex])    // "my-book"
            self.fileExtension = ext
            self.originalStem = stemPart
            self._stem = State(initialValue: stemPart)
        } else {
            // No extension (folder or extensionless file) — edit the full name
            self.fileExtension = ""
            self.originalStem = name
            self._stem = State(initialValue: name)
        }
    }

    /// The full name that will be sent to the device.
    private var fullName: String {
        stem.trimmingCharacters(in: .whitespaces) + fileExtension
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        TextField("Name", text: $stem)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .onChange(of: stem) {
                                validationError = nil
                            }
                            .onSubmit {
                                Task { await rename() }
                            }

                        if !fileExtension.isEmpty {
                            Text(fileExtension)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Rename \"\(file.name)\"")
                } footer: {
                    if let error = validationError {
                        Text(error)
                            .foregroundStyle(AppColor.error)
                    } else if !fileExtension.isEmpty {
                        Text("The file extension cannot be changed.")
                    }
                }
            }
            .navigationTitle("Rename")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        Task { await rename() }
                    }
                    .disabled(
                        stem.trimmingCharacters(in: .whitespaces).isEmpty
                        || stem.trimmingCharacters(in: .whitespaces) == originalStem
                        || isRenaming
                    )
                }
            }
            .interactiveDismissDisabled(isRenaming)
        }
        .presentationDetents([.medium])
    }

    private func rename() async {
        let trimmedStem = stem.trimmingCharacters(in: .whitespaces)

        guard trimmedStem != originalStem else {
            dismiss()
            return
        }

        if let error = FileNameValidator.validate(trimmedStem) {
            validationError = error
            return
        }

        let newName = trimmedStem + fileExtension

        isRenaming = true
        let success = await onRename(newName)
        isRenaming = false

        if success {
            dismiss()
        }
    }
}
