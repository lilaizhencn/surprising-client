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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiquidGlassNavigation") {
      registrar.register(LiquidGlassViewFactory(), withId: "surprising/liquid-glass")
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GoogleLoginConfiguration") {
      let channel = FlutterMethodChannel(name: "surprising/google-login", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "isConfigured", let clientId = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        let expected = clientId.split(separator: ".").reversed().joined(separator: ".")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        result(schemes.contains(expected))
      }
    }
  }
}
