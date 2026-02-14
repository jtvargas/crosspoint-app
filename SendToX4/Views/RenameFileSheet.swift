import SwiftUI

/// Sheet for renaming a file on the device.
struct RenameFileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let file: DeviceFile
    var onRename: (String) async -> Bool

    @State private var newName: String
    @State private var validationError: String?
    @State private var isRenaming = false

    init(file: DeviceFile, onRename: @escaping (String) async -> Bool) {
        self.file = file
        self.onRename = onRename
        self._newName = State(initialValue: file.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("File name", text: $newName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: newName) {
                            validationError = nil
                        }
                        .onSubmit {
                            Task { await rename() }
                        }
                } header: {
                    Text("Rename \"\(file.name)\"")
                } footer: {
                    if let error = validationError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        Task { await rename() }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName == file.name || isRenaming)
                }
            }
            .interactiveDismissDisabled(isRenaming)
        }
        .presentationDetents([.medium])
    }

    private func rename() async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)

        guard trimmed != file.name else {
            dismiss()
            return
        }

        if let error = FileNameValidator.validate(trimmed) {
            validationError = error
            return
        }

        isRenaming = true
        let success = await onRename(trimmed)
        isRenaming = false

        if success {
            dismiss()
        }
    }
}
