import SwiftUI

@main
struct CameraFileSortSwiftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(idealWidth: 780, idealHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
