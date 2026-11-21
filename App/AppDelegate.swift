import UIKit
import WaoCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Made at launch rather than with the UI: iOS may relaunch the app in the background only to hand it a
    /// finished transfer, and the session must exist under the same identifier to receive it.
    static let downloader = ModelDownloader(
        store: ModelStore(directory: ModelStore.defaultDirectory),
        configuration: .background(withIdentifier: "com.peerasak.wao.model-download"))

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = Self.downloader
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        nonisolated(unsafe) let completion = completionHandler
        Self.downloader.handleBackgroundEvents { completion() }
    }
}
