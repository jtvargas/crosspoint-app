import SwiftUI

/// Sheet for creating a new folder on the device.
struct CreateFolderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onCreate: (String) async -> Bool

    @State private var folderName = ""
    @State private var validationError: String?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $folderName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: folderName) {
                            // Clear validation error as user types
                            validationError = nil
                        }
                        .onSubmit {
                            Task { await create() }
                        }
                } footer: {
                    if let error = validationError {
                        Text(error)
                            .foregroundStyle(AppColor.error)
                    } else {
                        Text("Avoid special characters: \" * : < > ? / \\ |")
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        let trimmed = folderName.trimmingCharacters(in: .whitespaces)

        if let error = FileNameValidator.validate(trimmed) {
            validationError = error
            return
        }

        isCreating = true
        let success = await onCreate(trimmed)
        isCreating = false

        if success {
            dismiss()
        }
    }
}
