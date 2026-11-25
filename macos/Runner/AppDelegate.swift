import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Tells the app about menu choices it handles itself ("codename/menu").
  private var menuChannel: FlutterMethodChannel?

  // Menu items the app handles, connected in MainMenu.xib.

  /// The app menu's Settings… (⌘,).
  @IBAction func openSettings(_ sender: Any?) { send("openSettings") }

  /// File › New Task (⌘N).
  @IBAction func newTask(_ sender: Any?) { send("newTask") }

  /// File › New Personal Task (⌥⌘N).
  @IBAction func newPersonalTask(_ sender: Any?) { send("newPersonalTask") }

  /// File › New Project (⇧⌘N).
  @IBAction func newProject(_ sender: Any?) { send("newProject") }

  private func send(_ method: String) {
    if menuChannel == nil,
      let flutter = mainFlutterWindow?.contentViewController as? FlutterViewController
    {
      menuChannel = FlutterMethodChannel(
        name: "codename/menu", binaryMessenger: flutter.engine.binaryMessenger)
    }
    menuChannel?.invokeMethod(method, arguments: nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
