import SwiftUI

/// About sheet with app info, developer introduction, promoted apps, and links.
struct AboutAppView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    Divider()
                    aboutSection
                    Divider()
                    myAppsSection
                    Divider()
                    linksSection
                }
                .padding()
                .padding(.bottom, 24)
            }
            .navigationTitle(loc(.aboutCrossX))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(.done)) { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            appIconImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.tertiary.opacity(0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("CrossX")
                    .font(.title2.bold())
                Text("\(loc(.version)) \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(.aboutHiLine))
                .font(.headline)

            Text(loc(.aboutDescription1))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(loc(.aboutDescription2))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(loc(.aboutDescription3))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - My Apps

    private var myAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc(.myApps))
                .font(.headline)

            ForEach(Self.otherApps) { app in
                AboutAppLinkRow(app: app)
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc(.feedbackAndSupport))
                .font(.headline)

            aboutLinkRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: loc(.sourceCode),
                subtitle: "github.com/jtvargas/crosspoint-app",
                url: Self.githubCodeURL
            )

            aboutLinkRow(
                icon: "lightbulb",
                title: loc(.featureRequests),
                subtitle: loc(.aboutFeatureRequestsSubtitle),
                url: Self.githubIssuesURL
            )
        }
    }

    private func aboutLinkRow(
        icon: String, title: String, subtitle: String, url: URL
    ) -> some View {
        Button { openURL(url) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppColor.accent, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var appIconImage: Image {
        #if canImport(UIKit)
        if let uiImage = UIImage(named: "icon-crossx") {
            return Image(uiImage: uiImage)
        }
        #elseif canImport(AppKit)
        return Image(nsImage: NSApp.applicationIconImage)
        #endif
        return Image(systemName: "cube.transparent.fill")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Static Data

    private static let githubCodeURL = URL(
        string: "https://github.com/jtvargas/crosspoint-app"
    )!
    private static let githubIssuesURL = URL(
        string: "https://github.com/jtvargas/crosspoint-app/issues/new/choose"
    )!

    private static let otherApps: [AboutAppLink] = [
        AboutAppLink(
            name: "Hit21: Blackjack Game",
            description: "Minimalistic Blackjack - Free",
            iconName: "suit.spade.fill",
            iconColor: .purple,
            url: URL(string: "https://apps.apple.com/us/app/hit21-blackjack-game/id6740510784")!,
            localImage: "hit21-icon"
        ),
        AboutAppLink(
            name: "SnipKey",
            description: "Clipboard snippets from your keyboard - Free",
            iconName: "keyboard",
            iconColor: .blue,
            url: URL(string: "https://apps.apple.com/us/app/snipkey/id6480381137")!,
            localImage: "snipkey-icon"
        ),
        AboutAppLink(
            name: "More Apps",
            description: "Browse all my published apps",
            iconName: "square.grid.2x2",
            iconColor: .teal,
            url: URL(string: "https://go.jrtv.space/apps")!
        ),
    ]
}

// MARK: - App Link Model

struct AboutAppLink: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let iconName: String
    let iconColor: Color
    let url: URL
    let localImage: String?

    init(name: String, description: String, iconName: String, iconColor: Color, url: URL, localImage: String? = nil) {
        self.name = name
        self.description = description
        self.iconName = iconName
        self.iconColor = iconColor
        self.url = url
        self.localImage = localImage
    }
}

// MARK: - App Link Row

private struct AboutAppLinkRow: View {
    let app: AboutAppLink
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(app.url) } label: {
            HStack(spacing: 12) {
                if let localImage = app.localImage {
                    Image(localImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: app.iconName)
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(app.iconColor, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline.weight(.semibold))
                    Text(app.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
