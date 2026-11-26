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

    // A link copied in a browser or the YouTube app is often only a URL on
    // the pasteboard, with no plain text that Flutter's clipboard reads.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SinaiClipboard")
    let channel = FlutterMethodChannel(
      name: "sinai/clipboard", binaryMessenger: registrar!.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "link" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let board = UIPasteboard.general
      result(board.url?.absoluteString ?? board.string)
    }

    // Google Sign-In crashes the app when it lacks its client ID or the
    // URL scheme for it, so the app asks first.
    let setup = FlutterMethodChannel(
      name: "sinai/setup", binaryMessenger: registrar!.messenger())
    setup.setMethodCallHandler { call, result in
      guard call.method == "googleSignInReady" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
        let config = NSDictionary(contentsOfFile: path),
        let reversed = config["REVERSED_CLIENT_ID"] as? String,
        config["CLIENT_ID"] is String
      else {
        result(false)
        return
      }
      let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
      let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
      result(schemes.contains(reversed))
    }
  }
}
