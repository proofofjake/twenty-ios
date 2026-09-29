import SwiftUI

@main
struct TwentyCRMApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .ready:
            MainTabView()
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
        List(app.otherObjects) { object in
            NavigationLink(object.labelPlural, value: Route.list(object: object.nameSingular))
        }
        .overlay {
            if app.otherObjects.isEmpty { ContentUnavailableView("No other objects", systemImage: "square.grid.2x2") }
        }
        .navigationTitle("More")
    }
}
