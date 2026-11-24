import Flutter
import UIKit

/// A small bridge to UIKit's own tab bar. No root controller replacement,
/// private API, Flutter snapshots or custom per-frame glass shader is needed.
final class LiquidGlassNavigationPlugin: NSObject, FlutterPlugin {
  static let channelName = "com.ngbyspy.piliplus/liquid_glass_navigation"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(LiquidGlassNavigationPlugin(), channel: channel)
    registrar.register(
      GlassNavigationFactory(messenger: registrar.messenger()),
      withId: "\(channelName)/view"
    )
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "isSupported" else {
      result(FlutterMethodNotImplemented)
      return
    }
    if #available(iOS 26.0, *) {
      result(true)
    } else {
      result(false)
    }
  }
}

private final class GlassNavigationFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    GlassNavigationView(frame: frame, id: viewId, args: args, messenger: messenger)
  }
}

private final class GlassNavigationHost: UIView {
  let bar = UITabBar(frame: .zero)
  var onHeight: ((CGFloat) -> Void)?
  private var lastHeight: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    bar.isTranslucent = true
    // Retain system materials, including Reduce Transparency/Motion behavior.
    // An opaque background or an extra blur would defeat the native glass.
    addSubview(bar)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    bar.frame = bounds
    guard window != nil, bounds.width > 0 else { return }
    let height = max(49, bar.sizeThatFits(CGSize(width: bounds.width, height: 0)).height)
    if abs(lastHeight - height) > 0.5 {
      lastHeight = height
      onHeight?(height)
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  func invalidateMetrics() {
    lastHeight = 0
    setNeedsLayout()
  }
}

private final class GlassNavigationView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let host: GlassNavigationHost
  private let channel: FlutterMethodChannel
  private var itemDefinitions: [[String: String]] = []

  init(frame: CGRect, id: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    host = GlassNavigationHost(frame: frame)
    channel = FlutterMethodChannel(
      name: "\(LiquidGlassNavigationPlugin.channelName)/\(id)",
      binaryMessenger: messenger
    )
    super.init()
    host.bar.delegate = self
    host.onHeight = { [weak self] height in
      self?.channel.invokeMethod("metrics", arguments: ["height": Double(height)])
    }
    update(args as? [String: Any] ?? [:])
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "arguments", message: "Missing configuration", details: nil))
        return
      }
      self.update(arguments)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { host }

  private func update(_ arguments: [String: Any]) {
    let entries = arguments["items"] as? [[String: Any]] ?? []
    let definitions = entries.map { entry in
      ["id": entry["id"] as? String ?? "",
       "label": entry["label"] as? String ?? "",
       "symbol": entry["symbol"] as? String ?? "",
       "selectedSymbol": entry["selectedSymbol"] as? String ?? ""]
    }
    // Do not recreate items during selection/appearance/badge updates. That
    // would interrupt UIKit's interactive glass lens and VoiceOver focus.
    if definitions != itemDefinitions {
      itemDefinitions = definitions
      let items = definitions.map { entry -> UITabBarItem in
        let item = UITabBarItem(
          title: entry["label"], image: UIImage(systemName: entry["symbol"] ?? ""),
          selectedImage: UIImage(systemName: entry["selectedSymbol"] ?? "")
        )
        item.accessibilityIdentifier = entry["id"]
        return item
      }
      host.bar.setItems(items, animated: false)
    }
    for (index, item) in (host.bar.items ?? []).enumerated() where index < entries.count {
      item.badgeValue = entries[index]["badge"] as? String
    }
    if let selectedId = arguments["selectedId"] as? String,
       let index = definitions.firstIndex(where: { $0["id"] == selectedId }),
       let items = host.bar.items, index < items.count,
       host.bar.selectedItem !== items[index] {
      host.bar.selectedItem = items[index]
    }
    host.overrideUserInterfaceStyle = (arguments["isDark"] as? Bool ?? false) ? .dark : .light
    host.semanticContentAttribute = (arguments["rtl"] as? Bool ?? false)
      ? .forceRightToLeft : .forceLeftToRight
    if let number = arguments["tint"] as? NSNumber {
      let value = number.uint32Value
      host.bar.tintColor = UIColor(
        red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255,
        alpha: CGFloat((value >> 24) & 255) / 255
      )
    }
    host.invalidateMetrics()
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(of: item), index < itemDefinitions.count,
          let id = itemDefinitions[index]["id"] else { return }
    // Repeated selections still reach Flutter's existing to-top/refresh logic.
    channel.invokeMethod("selected", arguments: ["id": id])
  }
}
