import SwiftUI

@main
struct TwentyCRMApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                #if DEBUG
                .overlay { LocalBuildFrame() }
                #endif
        }
    }
}

#if DEBUG
/// Orange frame around the screen on local (Debug) builds, so they're never
/// confused with the TestFlight app. Release builds don't compile this.
private struct LocalBuildFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Self.displayCornerRadius, style: .continuous)
            .strokeBorder(Color.orange, lineWidth: 4)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Follows the display's rounded corners on Face ID iPhones (~55pt);
    /// square on home-button screens, which have no bottom safe area.
    private static var displayCornerRadius: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let bottom = scene?.windows.first?.safeAreaInsets.bottom ?? 0
        return bottom > 0 ? 55 : 0
    }
}
#endif

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .ready:
            MainTabView()
                .overlay(alignment: .bottom) {
                    if let action = app.undoBanner {
                        UndoBanner(action: action)
                            .padding(.bottom, 96) // clear of the tab bar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: app.undoBanner?.id)
        case .loading:
            ProgressView("Loading workspace…")
        case .disconnected:
            ConnectView()
        case .failed(let message):
            if app.service == nil {
                ConnectView(error: message)
            } else {
                ContentUnavailableView {
                    Label("Couldn't load workspace", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await app.loadSchema() } }.buttonStyle(.borderedProminent)
                    Button("Change connection") { app.disconnect() }
                }
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            if let people = app.object(named: "person") {
                RouteStack { RecordListView(object: people) }
                    .tabItem { Label(people.labelPlural, systemImage: "person.2") }
            }
            if let companies = app.object(named: "company") {
                RouteStack { RecordListView(object: companies) }
                    .tabItem { Label(companies.labelPlural, systemImage: "building.2") }
            }
            RouteStack { MoreObjectsView() }
                .tabItem { Label("More", systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct MoreObjectsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            #if DEBUG
            // Local builds only: review Claude's guesses for empty company fields.
            if app.object(named: "company") != nil {
                Section { ClaudeGuessesRow() }
            }
            #endif
            Section {
                ForEach(app.otherObjects) { object in
                    NavigationLink(object.labelPlural, value: Route.list(object: object.nameSingular))
                }
            }
        }
        .overlay {
            if app.otherObjects.isEmpty, !hasDebugRows { ContentUnavailableView("No other objects", systemImage: "square.grid.2x2") }
        }
        .navigationTitle("More")
    }

    private var hasDebugRows: Bool {
        #if DEBUG
        app.object(named: "company") != nil
        #else
        false
        #endif
    }
}
