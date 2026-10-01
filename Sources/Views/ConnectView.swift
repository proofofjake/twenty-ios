import SwiftUI

struct ConnectView: View {
    @Environment(AppModel.self) private var app
    var error: String?

    @State private var serverURL = ""
    @State private var workspaceURL = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var isSigningIn = false
    @State private var showsAPIKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.twenty.com", text: $serverURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connect.server")
                } header: {
                    Text("Server")
                } footer: {
                    Text("Twenty Cloud is https://api.twenty.com. For self-hosted, use your own domain.")
                }
                Section {
                    TextField("https://yourteam.twenty.com", text: $workspaceURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("connect.workspace")
                    Button {
                        isSigningIn = true
                        Task {
                            await app.signIn(serverURL: serverURL, workspaceURL: workspaceURL)
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.headline)
                            if isSigningIn { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isSigningIn || isConnecting)
                    .accessibilityIdentifier("connect.signIn")
                } header: {
                    Text("Workspace")
                } footer: {
                    Text("The address you open Twenty at. Sign in opens its login page; use Continue with Google, as on the web. Records you add are credited to you, and companies get you as Account Owner.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    DisclosureGroup("Use an API key instead", isExpanded: $showsAPIKey) {
                        HStack {
                            SecureField("API key", text: $apiKey)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("connect.key")
                            // Keys are long JWTs; copy on the Mac and paste here via Universal Clipboard.
                            PasteButton(payloadType: String.self) { strings in
                                if let key = strings.first { apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines) }
                            }
                            .labelStyle(.iconOnly)
                            .buttonBorderShape(.capsule)
                        }
                        Button {
                            isConnecting = true
                            Task {
                                await app.connect(serverURL: serverURL, apiKey: apiKey)
                                isConnecting = false
                            }
                        } label: {
                            HStack {
                                Text("Connect with key")
                                if isConnecting { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isConnecting || isSigningIn || apiKey.isEmpty)
                    }
                } footer: {
                    if showsAPIKey {
                        Text("Create one in Twenty under Settings → APIs & Webhooks; it's kept in the iOS Keychain. A key acts as the whole workspace, so records aren't credited to anyone.")
                    }
                }
                Section {
                    Button("Try demo data") { Task { await app.startDemo() } }
                        .accessibilityIdentifier("connect.demo")
                }
            }
            .navigationTitle("Connect to Twenty")
            .onAppear {
                if serverURL.isEmpty { serverURL = app.serverURL }
                if workspaceURL.isEmpty { workspaceURL = app.workspaceURL }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Server", value: app.isDemo ? "Demo data" : app.serverURL)
                if !app.isDemo {
                    LabeledContent("Signed in as", value: app.currentMember.map { FieldFormatter.relationTitle(.object($0.values)) }
                        ?? (app.isSignedIn ? "…" : "API key"))
                }
                LabeledContent("Objects", value: "\(app.objects.count)")
                Button("Reload schema") { Task { await app.loadSchema() } }
            }
            RecentActionsSection()
            Section {
                Button(app.isDemo ? "Leave demo" : app.isSignedIn ? "Sign out" : "Disconnect", role: .destructive) { app.disconnect() }
            } footer: {
                if !app.isDemo {
                    Text(app.isSignedIn ? "Signing out ends this app's access to your account." : "Disconnecting removes the API key from this device.")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
