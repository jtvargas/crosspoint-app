import Testing
@testable import SendToX4

@MainActor
struct ToastManagerTests {

    @Test func failureImmediatelyReplacesSuccessWithNewReadingTime() throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showSuccess("Sent", subtitle: "Previous article")
        let success = try #require(manager.hud)

        manager.showError("Send failed", subtitle: "Device disconnected")
        let failure = try #require(manager.hud)

        #expect(failure.id != success.id)
        #expect(failure.kind == .error)
        #expect(failure.title == "Send failed")
        #expect(failure.subtitle == "Device disconnected")
        #expect(failure.duration == 4)
        #expect(failure.duration > success.duration)

        manager.dismissHUD(id: success.id)
        #expect(manager.hud == failure)
        manager.dismissHUD(id: failure.id)
        #expect(manager.hud == nil)
    }

    @Test func identicalFailuresAreNewRequestsAndIgnoreStaleDismissal() throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showError("Send failed", subtitle: "Device disconnected")
        let first = try #require(manager.hud)

        manager.showError("Send failed", subtitle: "Device disconnected")
        let repeated = try #require(manager.hud)

        #expect(repeated.id != first.id)
        manager.dismissHUD(id: first.id)
        #expect(manager.hud == repeated)
        manager.dismissHUD(id: repeated.id)
        #expect(manager.hud == nil)
    }

    @Test func repeatedCenterRequestsIgnoreOldDismissalsWithoutReplacingHUD() throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showError("Send failed")
        let failure = try #require(manager.hud)
        manager.showCopied("Copied")
        let first = try #require(manager.center)

        manager.showCopied("Copied")
        let repeated = try #require(manager.center)

        #expect(repeated.id != first.id)
        #expect(manager.hud == failure)
        manager.dismissCenter(id: first.id)
        #expect(manager.center == repeated)
        manager.dismissCenter(id: repeated.id)
        #expect(manager.center == nil)
        #expect(manager.hud == failure)
    }

    @Test func hudReplacementAndDismissalPreserveCenterRequest() throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showCopied("Copied")
        let copied = try #require(manager.center)
        manager.showSuccess("Sent")
        let success = try #require(manager.hud)

        manager.showError("Send failed")
        let failure = try #require(manager.hud)
        #expect(manager.center == copied)

        manager.dismissHUD(id: success.id)
        #expect(manager.hud == failure)
        #expect(manager.center == copied)
        manager.dismissHUD(id: failure.id)
        #expect(manager.hud == nil)
        #expect(manager.center == copied)
    }

    @Test(arguments: [false, true])
    func nonErrorReplacementRestoresNormalDuration(queued: Bool) throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showError("Send failed", subtitle: "Device disconnected")
        let failure = try #require(manager.hud)

        if queued {
            manager.showQueued("Waiting for device")
        } else {
            manager.showSuccess("Sent")
        }
        let replacement = try #require(manager.hud)

        #expect(replacement.id != failure.id)
        #expect(replacement.kind == (queued ? .queued : .success))
        #expect(replacement.duration == 2.5)
        #expect(replacement.subtitle == nil)
        manager.dismissHUD(id: failure.id)
        #expect(manager.hud == replacement)
    }

    @Test(arguments: [
        (nil as String?, nil as String?),
        ("", nil),
        (" \t\r\n\u{00A0}\u{2003} ", nil),
        ("  Device\t\t disconnected\r\n Try\u{00A0}again  ", "Device disconnected Try again")
    ])
    func errorSubtitleNormalizesWhitespace(input: String?, expected: String?) throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        manager.showError("Send failed", subtitle: "Previous detail")

        manager.showError("Send failed", subtitle: input)

        let failure = try #require(manager.hud)
        #expect(failure.subtitle == expected)
    }

    @Test(arguments: [119, 120, 121])
    func errorSubtitleLimitCountsWholeUnicodeCharacters(length: Int) throws {
        let manager = ToastManager()
        defer { dismissAll(manager) }
        // Each unit contains multiple Unicode scalars but is one Character.
        let grapheme = "e\u{0301}\u{0323}"
        let detail = String(repeating: grapheme, count: length)

        manager.showError("Send failed", subtitle: " \n" + detail + "\t ")

        let subtitle = try #require(manager.hud?.subtitle)
        let expected = length <= 120 ? detail : String(repeating: grapheme, count: 117) + "..."
        #expect(subtitle == expected)
        #expect(subtitle.count == min(length, 120))
    }

    private func dismissAll(_ manager: ToastManager) {
        if let hud = manager.hud {
            manager.dismissHUD(id: hud.id)
        }
        if let center = manager.center {
            manager.dismissCenter(id: center.id)
        }
    }
}
