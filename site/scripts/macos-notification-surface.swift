import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

guard let screen = NSScreen.main else {
  FileHandle.standardError.write(Data("No active macOS display is available.\n".utf8))
  exit(1)
}

let window = NSWindow(
  contentRect: screen.frame,
  styleMask: [.borderless],
  backing: .buffered,
  defer: false,
  screen: screen
)

// A deterministic Ceibo blue-black surface keeps the notification's native
// translucency while avoiding personal wallpaper, open apps, and menu-bar data.
window.backgroundColor = NSColor(
  calibratedRed: 2.0 / 255.0,
  green: 8.0 / 255.0,
  blue: 23.0 / 255.0,
  alpha: 1.0
)
window.level = .normal
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
window.ignoresMouseEvents = true
window.orderFrontRegardless()
application.activate(ignoringOtherApps: true)

application.run()
