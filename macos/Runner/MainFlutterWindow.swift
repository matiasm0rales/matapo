import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The UI is laid out for a 1080p TV (960 × 540 logical): start at 720p
    // and never go smaller than that layout.
    self.title = "Topo TV"
    self.contentMinSize = NSSize(width: 960, height: 540)
    self.setContentSize(NSSize(width: 1280, height: 720))
    self.center()
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlayerChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Same "topo/player" channel as MainActivity.kt on Android, so
  /// Snapshots (lib/player/stream_queue.dart) works unchanged.
  private func registerPlayerChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "topo/player", binaryMessenger: messenger)
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
}
