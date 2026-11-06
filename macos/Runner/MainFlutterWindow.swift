import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.title = "Matapo"
    self.contentMinSize = NSSize(width: 820, height: 520)
    self.setContentSize(NSSize(width: 1280, height: 720))
    self.center()
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlayerChannel(flutterViewController.engine.binaryMessenger)
    registerWindowChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Same "matapo/player" channel as MainActivity.kt on Android, so
  /// Snapshots (lib/player/stream_queue.dart) works unchanged.
  private func registerPlayerChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "matapo/player", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      // Where the player saves last-frame snapshots (app cache).
      case "snapshotDir":
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Full screen for the live view's button and the F shortcut.
  private func registerWindowChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "matapo/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "toggleFullScreen":
        self?.toggleFullScreen(nil)
        result(nil)
      case "isFullScreen":
        result(self?.styleMask.contains(.fullScreen) ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
