import OfflineFirstFramework
import SwiftUI

@main
struct OfflineTodosApp: App {
    @State private var model = DemoModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TodoListView(model: model)
                .task { await model.start(sample: UserDefaults.standard.string(forKey: "sample")) }
        }
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        // Info.plist lists this identifier under BGTaskSchedulerPermittedIdentifiers; the system
        // runs the closure when it grants background time after BackgroundRefresh.schedule().
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [store = model.store] in
            await BackgroundRefresh.run(store: store)
        }
        #endif
    }
}
