import AppKit
import Foundation

// Notification banners are rendered inside Notification Center's screen-sized
// compositing window on current macOS releases, not as standalone CGWindows.
// Return the stable 360x80-point banner region on the menu-bar display instead
// of accidentally selecting a similarly sized Notification Center widget.
guard let screen = NSScreen.screens.first else {
  FileHandle.standardError.write(Data("No active macOS display is available.\n".utf8))
  exit(1)
}

let bannerWidth = min(360, screen.frame.width - 16)
let bannerHeight = min(80, screen.frame.height - 49)
let x = screen.frame.maxX - bannerWidth - 8
let y = 41.0

print(String(format: "%.0f,%.0f,%.0f,%.0f", x, y, bannerWidth, bannerHeight))
