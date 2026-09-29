import AppKit
import StickyCalendarCore
import SwiftUI

/// The About window: what the app is, its version, where to learn more, and credits.
struct AboutView: View {
    let updateChecker: UpdateChecker

    private static let repository = URL(string: "https://github.com/\(GitHubReleaseFetcher.repository)")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 3) {
                Text("Sticky Calendar").font(.system(size: 20, weight: .bold))
                Text("Version \(AppVersion.short) (build \(AppVersion.build))")
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Your day as a floating timeline, with a note and your reminders beside it.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Website", destination: Self.repository)
                Link("What's New", destination: Self.repository.appendingPathComponent("blob/master/CHANGELOG.md"))
                Link("Report an Issue", destination: Self.repository.appendingPathComponent("issues/new"))
            }
            .font(.callout)
            Button("Check for Updates…") { UpdateActions.checkFromMenu(updateChecker) }
                .disabled(updateChecker.isDevelopmentBuild)
            Divider()
            VStack(spacing: 4) {
                Text("Math is typeset with SwiftMath (MIT License) and the Latin Modern Math font (GUST Font License).")
                Text("© 2026 Pavel Ievlev")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 340)
    }
}
