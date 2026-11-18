import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.title = "QuotaRoom"
    self.setContentSize(NSSize(width: 1280, height: 860))
    self.minSize = NSSize(width: 900, height: 620)
    self.center()
    self.setFrame(self.frame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
