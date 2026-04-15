import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Set a larger initial window size for better UI layout
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width: CGFloat = 1100
    let height: CGFloat = 720
    let x = screenFrame.origin.x + (screenFrame.width - width) / 2
    let y = screenFrame.origin.y + (screenFrame.height - height) / 2
    let windowFrame = NSRect(x: x, y: y, width: width, height: height)

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 800, height: 600)
    self.title = "NEZ-ZFA"

    // Method channel for window control
    let channel = FlutterMethodChannel(name: "com.nez/window",
                                       binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      if call.method == "fitToAspectRatio" {
        let args = call.arguments as? [String: Any]
        let chromeHeight = args?["chromeHeight"] as? CGFloat ?? 80.0
        let currentWidth = self.frame.width
        // NES aspect ratio: 256:240
        let nesHeight = currentWidth * (240.0 / 256.0)
        let newHeight = nesHeight + chromeHeight
        let newFrame = NSRect(x: self.frame.origin.x,
                              y: self.frame.origin.y + self.frame.height - newHeight,
                              width: currentWidth,
                              height: newHeight)
        self.setFrame(newFrame, display: true, animate: true)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
