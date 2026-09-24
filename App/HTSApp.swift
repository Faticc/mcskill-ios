import HTSCore
import SwiftUI

@main
struct HTSApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

/** Edge to edge without system bars, landscape, like the game (and the Android launcher). */
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            GlowBackground(glow: model.glow)
            if model.session == nil {
                AuthScreen(flow: model.login)
            } else {
                HomeScreen()
            }
            OverlayHost(overlay: model.overlay)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
