import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    
    // 设置默认窗口大小
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let windowWidth: CGFloat = 1280
    let windowHeight: CGFloat = 800
    let windowX = (screenFrame.width - windowWidth) / 2 + screenFrame.origin.x
    let windowY = (screenFrame.height - windowHeight) / 2 + screenFrame.origin.y
    let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
    
    self.contentViewController = flutterViewController
    self.setFrame(newFrame, display: true)
    
    // 设置最小窗口大小
    self.minSize = NSSize(width: 900, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
