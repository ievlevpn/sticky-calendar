import AppKit
import StickyCalendarCore

/// What the menu and Settings do with update results. Never installs anything itself:
/// Homebrew installs are told to run `brew upgrade`, others get the release page.
@MainActor
enum UpdateActions {
    /// "Check for Updates…" from the menu: always reports the outcome in an alert.
    static func checkFromMenu(_ checker: UpdateChecker) {
        Task {
            let status = await checker.checkNow()
            let alert = NSAlert()
            switch status {
            case .available(let info):
                alert.messageText = "Sticky Calendar \(info.version) is available"
                alert.informativeText = "You have version \(checker.currentVersion)."
                alert.addButton(withTitle: "Get Update")
                alert.addButton(withTitle: "Later")
                if run(alert) == .alertFirstButtonReturn { getUpdate(info) }
                return
            case .upToDate:
                alert.messageText = "You're up to date"
                alert.informativeText = "Sticky Calendar \(checker.currentVersion) is the latest version."
            case .unknown:
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = checker.isDevelopmentBuild
                    ? "This is a development build; update checks are off."
                    : "Please try again later."
            }
            run(alert)
        }
    }

    static func getUpdate(_ info: ReleaseInfo) {
        guard InstallMethod.detect() == .homebrew else {
            NSWorkspace.shared.open(info.pageURL)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(InstallMethod.upgradeCommand, forType: .string)
        let alert = NSAlert()
        alert.messageText = "Update command copied"
        alert.informativeText = "Sticky Calendar was installed with Homebrew. Paste the copied command into Terminal to update:\n\n\(InstallMethod.upgradeCommand)"
        run(alert)
    }

    @discardableResult
    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
