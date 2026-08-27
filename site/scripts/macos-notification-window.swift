import CoreGraphics
import Foundation

struct Candidate {
  let id: CGWindowID
  let owner: String
  let name: String
  let bounds: CGRect
  let layer: Int
  let alpha: Double
}

guard let rawWindows = CGWindowListCopyWindowInfo(
  [.optionOnScreenOnly, .excludeDesktopElements],
  kCGNullWindowID
) as? [[String: Any]] else {
  FileHandle.standardError.write(Data("Unable to enumerate on-screen windows.\n".utf8))
  exit(1)
}

let windows = rawWindows.compactMap { info -> Candidate? in
  guard
    let number = info[kCGWindowNumber as String] as? NSNumber,
    let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
  else {
    return nil
  }

  return Candidate(
    id: CGWindowID(number.uint32Value),
    owner: info[kCGWindowOwnerName as String] as? String ?? "",
    name: info[kCGWindowName as String] as? String ?? "",
    bounds: bounds,
    layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
    alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
  )
}

let notifications = windows.filter { window in
  let owner = window.owner.lowercased()
  let plausibleSize = (250 ... 900).contains(window.bounds.width)
    && (50 ... 360).contains(window.bounds.height)
  return owner.contains("notification") && plausibleSize && window.alpha > 0
}.sorted { lhs, rhs in
  if lhs.layer != rhs.layer { return lhs.layer > rhs.layer }
  if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY < rhs.bounds.minY }
  if lhs.bounds.maxX != rhs.bounds.maxX { return lhs.bounds.maxX > rhs.bounds.maxX }
  return lhs.bounds.width * lhs.bounds.height > rhs.bounds.width * rhs.bounds.height
}

if let notification = notifications.first {
  print(notification.id)
  exit(0)
}

FileHandle.standardError.write(Data("No visible Notification Center banner was found. On-screen windows:\n".utf8))
for window in windows.sorted(by: { $0.layer > $1.layer }) {
  let line = String(
    format: "id=%u owner=%@ name=%@ layer=%d alpha=%.2f bounds=%.0fx%.0f+%.0f+%.0f\n",
    window.id,
    window.owner,
    window.name,
    window.layer,
    window.alpha,
    window.bounds.width,
    window.bounds.height,
    window.bounds.minX,
    window.bounds.minY
  )
  FileHandle.standardError.write(Data(line.utf8))
}
exit(1)
