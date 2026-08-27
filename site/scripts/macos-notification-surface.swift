import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

guard !NSScreen.screens.isEmpty else {
  FileHandle.standardError.write(Data("No active macOS display is available.\n".utf8))
  exit(1)
}

// Keep strong references for the lifetime of the capture helper.
let windows = NSScreen.screens.map { screen -> NSWindow in
  let window = NSWindow(
    contentRect: screen.frame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false,
    screen: screen
  )

  // A deterministic Ceibo blue-black surface keeps the notification's native
  // translucency while hiding wallpaper, applications, icons, and menu-bar data.
  window.backgroundColor = NSColor(
    calibratedRed: 2.0 / 255.0,
    green: 8.0 / 255.0,
    blue: 23.0 / 255.0,
    alpha: 1.0
  )
  // Notification Center currently composites at layer 21. Layer 20 covers every
  // personal surface while remaining immediately below the real system banner.
  window.level = NSWindow.Level(rawValue: 20)
  window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
  window.ignoresMouseEvents = true
  window.orderFrontRegardless()
  return window
}

application.activate(ignoringOtherApps: true)
application.run()
