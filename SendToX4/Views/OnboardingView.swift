import SwiftUI

/// Multi-step onboarding shown on first app launch.
///
/// Uses a paged `TabView` on iOS for native swipe navigation with dots,
/// and a button-based stepper on macOS. Persisted via `@AppStorage` so it
/// only appears once — can be replayed from Settings.
struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0

    private let pageCount = 5

    var body: some View {
        ZStack(alignment: .topTrailing) {
            #if os(iOS)
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                convertPage.tag(1)
                queuePage.tag(2)
                shortcutPage.tag(3)
                getStartedPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #else
            VStack(spacing: 0) {
                Group {
                    switch currentPage {
                    case 0: welcomePage
                    case 1: convertPage
                    case 2: queuePage
                    case 3: shortcutPage
                    case 4: getStartedPage
                    default: welcomePage
                    }
                }
                .frame(maxHeight: .infinity)

                // macOS navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button(loc(.back)) {
                            withAnimation { currentPage -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    // Page indicator
                    HStack(spacing: 6) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? AppColor.accent : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Spacer()

                    if currentPage < pageCount - 1 {
                        Button(loc(.next)) {
                            withAnimation { currentPage += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.accent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            #endif

            // Skip button (hidden on last page)
            if currentPage < pageCount - 1 {
                Button(loc(.skip)) {
                    hasSeenOnboarding = true
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 24)
                .padding(.top, 16)
            }
        }
        #if os(iOS)
        .ignoresSafeArea(edges: .bottom)
        #endif
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        OnboardingPage(
            icon: "doc.text.magnifyingglass",
            title: loc(.welcomeTitle),
            description: loc(.welcomeDescription)
        )
    }

    // MARK: - Page 2: Convert

    private var convertPage: some View {
        OnboardingPage(
            icon: "link",
            title: loc(.pasteConvertRead),
            description: loc(.pasteConvertReadDescription)
        ) {
            HStack(spacing: 12) {
                pipelineStep(icon: "globe", label: loc(.fetch))
                pipelineArrow
                pipelineStep(icon: "text.magnifyingglass", label: loc(.extract))
                pipelineArrow
                pipelineStep(icon: "book.closed.fill", label: loc(.epub))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    // MARK: - Page 3: Queue

    private var queuePage: some View {
        OnboardingPage(
            icon: "tray.full.fill",
            title: loc(.worksOffline),
            description: loc(.worksOfflineDescription)
        ) {
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.title2)
                        .foregroundStyle(AppColor.accent)
                    Text(loc(.tabConvert))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                        .foregroundStyle(AppColor.warning)
                    Text(loc(.queueLabel))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .font(.title2)
                        .foregroundStyle(AppColor.success)
                    Text(loc(.sendLabel))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Page 4: Siri Shortcut

    private var shortcutPage: some View {
        OnboardingPage(
            icon: "wand.and.stars",
            title: loc(.convertFromAnywhere),
            description: loc(.convertFromAnywhereDescription)
        ) {
            VStack(spacing: 10) {
                shortcutStep(1, loc(.siriStep1))
                shortcutStep(2, loc(.siriStep2))
                shortcutStep(3, loc(.siriStep3))
                shortcutStep(3, loc(.siriStep4))
                shortcutStep(4, loc(.siriStep5))
                shortcutStep(5, loc(.siriStep6))
                shortcutStep(6, loc(.siriStep7))
                shortcutStep(7, loc(.siriStep8))
                shortcutStep(8, loc(.siriStep9))
                shortcutStep(9, loc(.done))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 32)
            .padding(.top, 4)

            #if os(iOS)
            Button {
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(loc(.openShortcutsApp), systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(AppColor.accent)
            .padding(.top, 12)
            #endif
        }
    }

    // MARK: - Page 5: Get Started

    private var getStartedPage: some View {
        OnboardingPage(
            icon: "checkmark.circle.fill",
            title: loc(.youreAllSet),
            description: loc(.youreAllSetDescription)
        ) {
            Button {
                hasSeenOnboarding = true
            } label: {
                Text(loc(.getStarted))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .padding(.horizontal, 40)
            .padding(.top, 16)
        }
    }

    // MARK: - Helpers

    private func pipelineStep(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.accent)
                .frame(width: 36, height: 36)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var pipelineArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func shortcutStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(AppColor.accent, in: .circle)

            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Onboarding Page Layout

/// Reusable page layout for onboarding screens.
///
/// Provides consistent spacing: icon → title → description → optional content.
private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let description: String
    @ViewBuilder var content: Content

    init(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(AppColor.accent)
                .padding(.bottom, 8)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            content

            Spacer()
            Spacer()
        }
        .padding(.top, 40)
    }
}
