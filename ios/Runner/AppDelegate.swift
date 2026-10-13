import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleMlStableDiffusionPlugin") {
      AppleMlStableDiffusionPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "A1111MiniBackgroundDownload") {
      BackgroundDownloadManager.shared.bind(messenger: registrar.messenger())
    }
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == BackgroundDownloadManager.sessionIdentifier {
      BackgroundDownloadManager.shared.setBackgroundCompletionHandler(completionHandler)
    } else {
      completionHandler()
    }
  }
}
