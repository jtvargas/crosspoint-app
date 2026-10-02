import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit

/// Native file-provider selection. Preparation owns the security-scoped sandbox copy.
struct ImportDocumentPicker: UIViewControllerRepresentable {
    var onSelect: (URL) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.epub, .pdf], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onSelect(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
#elseif os(macOS)
import AppKit

struct ImportDocumentPicker: NSViewControllerRepresentable {
    var onSelect: (URL) -> Void
    var onCancel: () -> Void

    func makeNSViewController(context: Context) -> PanelController {
        PanelController(onSelect: onSelect, onCancel: onCancel)
    }

    func updateNSViewController(_ controller: PanelController, context: Context) {}

    @MainActor
    final class PanelController: NSViewController {
        private let onSelect: (URL) -> Void
        private let onCancel: () -> Void
        private var panel: NSOpenPanel?
        private var hasPresented = false

        init(onSelect: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            guard !hasPresented, let window = view.window else { return }
            hasPresented = true
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.epub, .pdf]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            self.panel = panel
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .OK, let url = panel.url {
                    onSelect(url)
                } else {
                    onCancel()
                }
                self.panel = nil
            }
        }

        override func viewWillDisappear() {
            panel?.cancel(nil)
            super.viewWillDisappear()
        }
    }
}
#endif
