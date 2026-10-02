import SwiftUI
import SwiftData

struct FileImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var importVM = FileImportViewModel()
    @State private var selectedURL: URL?
    @State private var showPicker = false
    @State private var successDrawn = false
    @State private var successCommitted = false
    @AccessibilityFocusState private var statusFocused: Bool

    var onShowQueue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(loc(.importFile))
                    .font(.headline)
                    .padding(.vertical, 12)
                Spacer(minLength: 16)
                Button(loc(.importClose), systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(importVM.isProcessing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 20) {
                    documentHero
                        .padding(.top, 12)

                    VStack(spacing: 10) {
                        Text(statusTitle)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($statusFocused)
                        Text(statusDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: statusTitle)

                    if !importVM.filename.isEmpty {
                        Label(importVM.importedTitle ?? importVM.filename, systemImage: "doc.text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(.quaternary, in: .rect(cornerRadius: 16))
                            .transition(.opacity)
                    }

                    if importVM.isProcessing {
                        importProgress
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .animation(.easeOut(duration: 0.2), value: importVM.isProcessing)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(.background)
        .interactiveDismissDisabled(importVM.isProcessing)
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(560), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        #else
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 600, minHeight: 500, idealHeight: 580)
        #endif
        .sheet(isPresented: $showPicker) {
            ImportDocumentPicker(
                onSelect: { url in
                    selectedURL = url
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
        .task(id: selectedURL) {
            guard let selectedURL else { return }
            await importVM.importFile(at: selectedURL, modelContext: modelContext)
        }
        .onChange(of: importVM.isSuccess) { _, succeeded in
            guard succeeded else { return }
            statusFocused = true
            withAnimation(.easeOut(duration: 0.3), completionCriteria: .logicallyComplete) {
                successDrawn = true
            } completion: {
                successCommitted = true
            }
        }
        .onChange(of: importVM.errorMessage) { _, message in
            if message != nil {
                statusFocused = true
            }
        }
    }

    // The same book stays in place from choosing a file through the final result.
    private var documentHero: some View {
        Image(systemName: "book.closed.fill")
            .font(.largeTitle.scaled(by: 1.5))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .foregroundStyle(AppColor.accent)
            .frame(width: 112, height: 112)
            .glassEffect(.regular.tint(AppColor.accent.opacity(0.12)), in: .rect(cornerRadius: 28))
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(AppColor.success)
                    Path { path in
                        path.move(to: CGPoint(x: 11, y: 21))
                        path.addLine(to: CGPoint(x: 18, y: 28))
                        path.addLine(to: CGPoint(x: 30, y: 14))
                    }
                    .trim(from: 0, to: reduceMotion || successDrawn ? 1 : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 42, height: 42)
                .opacity(importVM.isSuccess && (!reduceMotion || successDrawn) ? 1 : 0)
                .phaseAnimator([1.0, 1.12, 1.0], trigger: successCommitted) { content, scale in
                    content.scaleEffect(reduceMotion ? 1 : scale)
                } animation: { _ in
                    .snappy(duration: 0.18)
                }
                .sensoryFeedback(.success, trigger: successCommitted) { _, newValue in newValue }
                .offset(x: 8, y: 8)
            }
            .padding(8)
            .accessibilityHidden(true)
    }

    private var importProgress: some View {
        VStack(spacing: 10) {
            if importVM.totalPages > 0 {
                ProgressView(
                    value: Double(importVM.completedPages),
                    total: Double(importVM.totalPages)
                )
                .tint(AppColor.accent)
                .accessibilityLabel(loc(.importProcessingTitle))
                .accessibilityValue(loc(.importPageProgress, importVM.completedPages, importVM.totalPages))

                Text(loc(.importPageProgress, importVM.completedPages, importVM.totalPages))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(importVM.completedPages)))
                    .animation(.easeOut(duration: 0.2), value: importVM.completedPages)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(loc(.importPreparing))
            }

            Text(importVM.totalPages > 0 && importVM.completedPages == importVM.totalPages
                 ? loc(.importFinishing) : loc(.importKeepOpen))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !importVM.isProcessing {
                Button(action: performPrimaryAction) {
                    Text(primaryActionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppColor.accent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .accessibilityIdentifier(importVM.isSuccess ? "show-import-queue" : "choose-import-file")
                .transition(.opacity)
            }

            if importVM.filename.isEmpty {
                Text(loc(.importDestination))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .animation(.easeOut(duration: 0.2), value: importVM.isProcessing)
    }

    private var statusTitle: String {
        if importVM.isSuccess { return loc(.importSuccessTitle) }
        if importVM.errorMessage != nil { return loc(.importErrorTitle) }
        if importVM.isProcessing { return loc(.importProcessingTitle) }
        return loc(.importTitle)
    }

    private var statusDescription: String {
        if importVM.isSuccess { return loc(.importSuccessDescription) }
        if let error = importVM.errorMessage { return error }
        if importVM.isProcessing {
            return importVM.totalPages > 0 ? loc(.importConverting) : loc(.importPreparing)
        }
        return loc(.importDescription)
    }

    private var primaryActionTitle: String {
        if importVM.isSuccess { return loc(.importShowQueue) }
        if importVM.errorMessage != nil { return loc(.importChooseAnother) }
        return loc(.importChooseFile)
    }

    private func performPrimaryAction() {
        if importVM.isSuccess {
            onShowQueue()
            dismiss()
        } else {
            selectedURL = nil
            importVM.reset()
            successDrawn = false
            successCommitted = false
            showPicker = true
        }
    }
}
