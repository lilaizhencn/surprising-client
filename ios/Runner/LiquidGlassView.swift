import Flutter
import UIKit

final class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    LiquidGlassView(frame: frame, arguments: args as? [String: Any] ?? [:])
  }
}

/// UIKit owns the material, including system transparency and contrast settings.
final class LiquidGlassView: NSObject, FlutterPlatformView {
  private let surface = UIVisualEffectView()
  private let color: UIColor
  private var observer: NSObjectProtocol?

  init(frame: CGRect, arguments: [String: Any]) {
    let argb = (arguments["tint"] as? NSNumber)?.uint32Value ?? 0xFF15171C
    color = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                    green: CGFloat((argb >> 8) & 255) / 255,
                    blue: CGFloat(argb & 255) / 255, alpha: 1)
    super.init()
    surface.frame = frame
    surface.isUserInteractionEnabled = false
    surface.isAccessibilityElement = false
    surface.overrideUserInterfaceStyle = (arguments["dark"] as? Bool ?? true) ? .dark : .light
    surface.layer.cornerRadius = CGFloat((arguments["radius"] as? NSNumber)?.doubleValue ?? 28)
    surface.clipsToBounds = true
    updateMaterial()
    observer = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil, queue: .main) { [weak self] _ in self?.updateMaterial() }
  }

  private func updateMaterial() {
    if UIAccessibility.isReduceTransparencyEnabled {
      surface.effect = nil
      surface.backgroundColor = color
    } else if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular)
      glass.tintColor = color.withAlphaComponent(0.72)
      glass.isInteractive = true
      surface.backgroundColor = .clear
      surface.effect = glass
    } else {
      surface.backgroundColor = color.withAlphaComponent(0.75)
      surface.effect = UIBlurEffect(style: .systemMaterial)
    }
  }

  func view() -> UIView { surface }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
