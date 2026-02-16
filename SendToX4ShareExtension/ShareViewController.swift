import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share Extension entry point.
/// Receives URLs from Safari and other apps, converts to EPUB, and sends to X4.
class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            close()
            return
        }
        
        let hostingView = UIHostingController(rootView: ShareExtensionView(
            itemProvider: itemProvider,
            onDismiss: { [weak self] in self?.close() }
        ))
        
        addChild(hostingView)
        view.addSubview(hostingView.view)
        hostingView.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingView.didMove(toParent: self)
    }
    
    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    let itemProvider: NSItemProvider
    let onDismiss: () -> Void
    
    @State private var status = loc(.preparing)
    @State private var isProcessing = true
    @State private var isSuccess = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            if isProcessing {
                ProgressView()
                    .controlSize(.large)
            } else if isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
            }
            
            Text(status)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(isProcessing ? loc(.cancel) : loc(.done)) {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
        .padding()
        .task {
            await processSharedURL()
        }
    }
    
    private func processSharedURL() async {
        // Extract URL from the shared item
        guard let url = await extractURL() else {
            status = loc(.invalidURL)
            errorMessage = loc(.couldNotExtractURL)
            isProcessing = false
            return
        }
        
        do {
            // Fetch
            status = loc(.phaseFetching)
            let page = try await WebPageFetcher.fetch(url: url)
            
            // Extract
            status = loc(.phaseExtracting)
            let content: ExtractedContent
            if let extracted = try ContentExtractor.extract(from: page.html, url: page.finalURL) {
                content = extracted
            } else {
                status = loc(.contentTooShort)
                errorMessage = loc(.couldNotExtractContent)
                isProcessing = false
                return
            }
            
            // Build EPUB
            status = loc(.phaseBuilding)
            let metadata = EPUBBuilder.Metadata(
                title: content.title,
                author: content.author ?? "Unknown",
                language: content.language,
                sourceURL: page.finalURL,
                description: content.description
            )
            let epubData = try EPUBBuilder.build(body: content.bodyHTML, metadata: metadata)
            let filename = FileNameGenerator.generate(
                title: content.title, author: content.author, url: page.finalURL
            )
            
            // Try to send to device
            status = loc(.connectingToX4)
            let discovery = await DeviceDiscovery.detect()
            
            if let service = discovery.service {
                status = loc(.phaseSending)
                try await service.ensureFolder("send-to-x4")
                try await service.uploadFile(data: epubData, filename: filename, toFolder: "send-to-x4")
                
                status = loc(.sentToX4)
                isSuccess = true
            } else {
                // Save to temp and offer share
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try epubData.write(to: tempURL)
                
                status = loc(.epubSaved)
                errorMessage = loc(.x4NotConnectedLocalEPUB)
                isSuccess = true
            }
            
        } catch {
            status = loc(.phaseFailed)
            errorMessage = error.localizedDescription
        }
        
        isProcessing = false
        
        // Auto-dismiss after 2 seconds on success
        if isSuccess {
            try? await Task.sleep(for: .seconds(2))
            onDismiss()
        }
    }
    
    private func extractURL() async -> URL? {
        // Try URL type first
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let url = item as? URL {
                        continuation.resume(returning: url)
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        // Try plain text (might be a URL string)
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        return nil
    }
}
