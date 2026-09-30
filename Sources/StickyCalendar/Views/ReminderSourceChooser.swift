import AppKit
import StickyCalendarCore
import SwiftUI

/// "Where should reminders come from?": shown the first time the reminders view opens, and
/// again after Settings → Reminders → Change Source or when a token stops working. A new
/// connection is tried (one real fetch) before it's saved.
struct ReminderSourceChooser: View {
    let store: ReminderStore
    let settings: ReminderSettings
    /// Start on this source's setup (e.g. to fix a rejected token).
    var initial: ReminderProvider?

    @State private var choice: ReminderProvider?
    @State private var token = ""
    @State private var vaultPath = ""
    @State private var inboxPath = "Inbox.md"
    @State private var isConnecting = false
    /// The last connection test to Things was refused by macOS.
    @State private var isThingsDenied = false
    @State private var error: String?
    /// The browser sign-in to Microsoft in progress.
    @State private var signIn: LoopbackRedirect?
    /// Cancel was pressed; whatever the sign-in then throws is not worth showing.
    @State private var signInCancelled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let choice {
                    setup(for: choice)
                } else {
                    Text("Where should reminders come from?")
                        .font(.headline)
                    ForEach(ReminderProvider.chooserCases, id: \.self) { provider in
                        Button { pick(provider) } label: { row(provider) }
                            .buttonStyle(.plain)
                            .disabled(!Self.isAvailable(provider))
                    }
                    Text("You can change this later in Settings → Reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .onAppear {
            if let initial { pick(initial) }
        }
        .onDisappear(perform: cancelSignIn)
    }

    // MARK: Parts

    private func row(_ provider: ReminderProvider) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.icon(provider))
                .font(.system(size: 16))
                .foregroundStyle(Self.tint(provider))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name).font(.system(size: 12.5, weight: .semibold))
                Text(Self.blurb(provider)).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
        .opacity(Self.isAvailable(provider) ? 1 : 0.5)
    }

    @ViewBuilder
    private func setup(for provider: ReminderProvider) -> some View {
        Button { cancelSignIn(); choice = nil; error = nil } label: {
            Label("All sources", systemImage: "chevron.left").font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        Label(provider.name, systemImage: Self.icon(provider)).font(.headline)
        switch provider {
        case .appleReminders:
            EmptyView()
        case .todoist, .tickTick:
            Text(provider == .todoist
                 ? "Paste your API token from Todoist → Settings → Integrations → Developer."
                 : "Paste your API token from TickTick → Settings → Account → API Token.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("API token", text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
            Button("Where do I find it?") {
                NSWorkspace.shared.open(provider == .todoist ? TodoistSource.tokenPage : TickTickSource.tokenPage)
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            Text("It's kept in your keychain.").font(.caption).foregroundStyle(.tertiary)
        case .obsidian:
            Text("Tasks (`- [ ]` lines) from every note in the vault, with 📅 due dates from the Tasks plugin. Each note is a list.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(vaultPath.isEmpty ? "No vault chosen" : (vaultPath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(vaultPath.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose Vault…", action: chooseVault)
            }
            HStack {
                Text("New reminders go to").font(.system(size: 11))
                TextField("Inbox.md", text: $inboxPath).textFieldStyle(.roundedBorder)
            }
        case .things:
            if store.access == .denied || isThingsDenied {
                Text("Sticky Calendar isn't allowed to control Things. Allow it in System Settings → Privacy & Security → Automation, under Sticky Calendar.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
                .font(.system(size: 11))
            } else {
                Text("To-dos from Things on this Mac: its Today, Inbox, projects and areas. macOS will ask whether Sticky Calendar may control Things.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .microsoftToDo:
            Text(store.access == .denied
                 ? "Microsoft To Do signed you out. Sign in again to continue."
                 : "Sign in with your Microsoft account in the browser. Sticky Calendar can then read and change your To Do tasks.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if signIn != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…").font(.system(size: 11))
                    Spacer()
                    Button("Cancel", action: cancelSignIn)
                }
            }
        }
        if let error {
            Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            if isConnecting { ProgressView().controlSize(.small) }
            Button(provider == .appleReminders ? "Use Apple Reminders" : provider == .microsoftToDo ? "Sign in with Microsoft" : "Connect", action: connect)
                .keyboardShortcut(.defaultAction)
                .disabled(isConnecting || !isReady(provider))
        }
    }

    // MARK: Actions

    private func pick(_ provider: ReminderProvider) {
        error = nil
        isThingsDenied = false
        choice = provider
        switch provider {
        case .todoist: token = ReminderTokens.token(for: TodoistSource.tokenAccount) ?? ""
        case .tickTick: token = ReminderTokens.token(for: TickTickSource.tokenAccount) ?? ""
        case .obsidian:
            vaultPath = settings.obsidianVaultPath ?? ""
            inboxPath = settings.obsidianInboxPath
        case .appleReminders, .things, .microsoftToDo: break
        }
    }

    private func isReady(_ provider: ReminderProvider) -> Bool {
        switch provider {
        case .appleReminders: true
        case .todoist, .tickTick: !token.trimmingCharacters(in: .whitespaces).isEmpty
        case .obsidian: !vaultPath.isEmpty
        case .things: true
        case .microsoftToDo: signIn == nil
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use as Vault"
        panel.message = "Choose your Obsidian vault folder."
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { vaultPath = url.path }
    }

    /// Tries the source with one fetch; only then saves the choice (and the token).
    private func connect() {
        guard let provider = choice, isReady(provider) else { return }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: ReminderSource
        switch provider {
        case .appleReminders: candidate = ReminderKitSource()
        case .todoist: candidate = TodoistSource(token: token)
        case .tickTick: candidate = TickTickSource(token: token)
        case .obsidian: candidate = ObsidianSource(vault: URL(fileURLWithPath: vaultPath), inboxPath: inboxPath)
        case .things: candidate = ThingsSource()
        case .microsoftToDo: return signInToMicrosoft()
        }
        isConnecting = true
        error = nil
        isThingsDenied = false
        Task {
            defer { isConnecting = false }
            if provider == .appleReminders {
                _ = await candidate.requestAccess()
            } else {
                guard candidate.currentAccess() == .granted else {
                    error = "That folder can't be read."
                    return
                }
                do {
                    _ = try await candidate.reminders(completedSince: Date())
                } catch {
                    self.error = error.localizedDescription
                    isThingsDenied = provider == .things && candidate.currentAccess() == .denied
                    return
                }
            }
            switch provider {
            case .todoist: ReminderTokens.setToken(token, for: TodoistSource.tokenAccount)
            case .tickTick: ReminderTokens.setToken(token, for: TickTickSource.tokenAccount)
            case .obsidian: settings.setObsidian(vault: vaultPath, inbox: inboxPath)
            case .appleReminders, .things, .microsoftToDo: break
            }
            settings.setProvider(provider)
            ReminderTokens.setToken(nil, for: MicrosoftAuth.tokenAccount)
            store.use(candidate)
        }
    }

    /// Stops a sign-in in progress: Cancel, Back and leaving the chooser all end up here.
    private func cancelSignIn() {
        guard let signIn else { return }
        signInCancelled = true
        signIn.cancel()
    }

    /// Browser sign-in: listen locally, open Microsoft's page, trade the code for tokens,
    /// try one fetch, then save.
    private func signInToMicrosoft() {
        let pkce = PKCE.make()
        let state = MicrosoftAuth.randomState()
        let redirect = LoopbackRedirect(state: state)
        signIn = redirect
        signInCancelled = false
        error = nil
        Task {
            defer { signIn = nil }
            do {
                let uri = try await redirect.start()
                NSWorkspace.shared.open(MicrosoftAuth.authorizeURL(redirect: uri, pkce: pkce, state: state))
                let code = try await redirect.code()
                let auth = MicrosoftSession(refreshToken: nil)
                try await auth.exchange(code: code, verifier: pkce.verifier, redirect: uri)
                // The exchange saved a refresh token; until the source is kept, take it back on any way out.
                var keep = false
                defer { if !keep { auth.signOut() } }
                if signInCancelled { return }
                let candidate = MicrosoftToDoSource(auth: auth)
                _ = try await candidate.reminders(completedSince: Date())
                if signInCancelled { return }
                keep = true
                settings.setProvider(.microsoftToDo)
                store.use(candidate)
                NSApp.activate()
            } catch {
                // Cancel can surface as any failure if it lands while the listener is starting.
                if signInCancelled { return }
                switch error {
                case LoopbackRedirect.Failure.cancelled:
                    return
                case LoopbackRedirect.Failure.timedOut:
                    self.error = "Signing in took too long. Try again."
                case LoopbackRedirect.Failure.denied(let reason):
                    self.error = "Microsoft didn't sign you in: \(reason)"
                default:
                    self.error = error.localizedDescription
                }
            }
        }
    }

    // MARK: Look

    static func isAvailable(_ provider: ReminderProvider) -> Bool {
        provider != .things || NSWorkspace.shared.urlForApplication(withBundleIdentifier: JXAThings.bundleID) != nil
    }

    static func icon(_ provider: ReminderProvider) -> String {
        switch provider {
        case .appleReminders: "checklist"
        case .todoist: "checkmark.circle"
        case .tickTick: "checkmark.square"
        case .obsidian: "doc.text"
        case .things: "checkmark.circle.fill"
        case .microsoftToDo: "checkmark.circle"
        }
    }

    static func tint(_ provider: ReminderProvider) -> Color {
        switch provider {
        case .appleReminders: .blue
        case .todoist: Color(.sRGB, red: 0.89, green: 0.27, blue: 0.2)
        case .tickTick: Color(.sRGB, red: 0.28, green: 0.45, blue: 0.98)
        case .obsidian: Color(.sRGB, red: 0.53, green: 0.36, blue: 0.96)
        case .things: Color(.sRGB, red: 0.23, green: 0.55, blue: 0.87)
        case .microsoftToDo: Color(.sRGB, red: 0.15, green: 0.39, blue: 0.81)
        }
    }

    static func blurb(_ provider: ReminderProvider) -> String {
        switch provider {
        case .appleReminders: "The Reminders app, synced with iCloud"
        case .todoist: "With your API token"
        case .tickTick: "With your API token"
        case .obsidian: "Tasks in your vault's notes"
        case .microsoftToDo: "Sign in with your Microsoft account"
        case .things: isAvailable(.things) ? "Things 3 on this Mac (beta)" : "Things isn't installed"
        }
    }
}
