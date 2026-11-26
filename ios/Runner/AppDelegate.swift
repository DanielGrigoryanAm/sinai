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
  }
}
