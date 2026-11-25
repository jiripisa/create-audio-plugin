// Capture the window of a process, found by its PID (never by app name).
//
//   swift scripts/capture_window.swift <pid> <out.png> [--wait 10]
//
// Finds the first on-screen window with kCGWindowOwnerPID == pid and layer 0 (waiting up to
// --wait seconds for it to appear), then runs `screencapture -x -o -l <window id> <out.png>`.
// It never captures without -l, so nothing but that window is ever read.
//
// Run it with the Bash sandbox disabled: inside the sandbox screencapture cannot reach the window
// server and fails as it does under a locked screen.
//
// Exit codes: 0 captured (prints the window id, its bounds and the image size in pixels),
//             2 usage error, 3 no window in time (no file written),
//             4 the image is all black (locked screen; the file is deleted),
//             5 screencapture gave no image (a locked screen, the sandbox, or no Screen Recording
//               permission). After 4 or 5 the capture is queued for when the user is back
//               (references/verification-kit.md); there is no other way to a window's picture.

import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
var wait = 10.0
if let i = args.firstIndex(of: "--wait") {
    guard i + 1 < args.count, let seconds = Double(args[i + 1]), seconds >= 0 else {
        fail("usage: capture_window.swift <pid> <out.png> [--wait seconds]", 2)
    }
    wait = seconds
    args.removeSubrange(i...(i + 1))
}
guard args.count == 2, let pid = Int32(args[0]), pid > 0 else {
    fail("usage: capture_window.swift <pid> <out.png> [--wait seconds]", 2)
}
let outPath = args[1]

struct Found { let id: Int; let width: Double; let height: Double }

func findWindow() -> Found? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let id = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              let width = b["Width"], let height = b["Height"], width > 0, height > 0
        else { continue }
        return Found(id: id, width: width, height: height)
    }
    return nil
}

let deadline = Date().addingTimeInterval(wait)
var window = findWindow()
while window == nil && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.25)
    window = findWindow()
}
guard let window else { fail("no on-screen window of pid \(pid) within \(wait) s", 3) }

try? FileManager.default.removeItem(atPath: outPath)
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l", String(window.id), outPath]
do { try capture.run() } catch { fail("cannot run screencapture: \(error)", 5) }
capture.waitUntilExit()
guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: outPath) else {
    fail("screencapture gave no image (status \(capture.terminationStatus)): a locked screen, the Bash sandbox "
         + "(run with it disabled) or no Screen Recording permission; queue the capture, do not retry", 5)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    try? FileManager.default.removeItem(atPath: outPath)
    fail("screencapture wrote an unreadable image", 5)
}

// All-black check: draw into an RGBA buffer and look for any non-zero colour byte.
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return true
}
if drew {
    var lit = false
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] | pixels[i + 1] | pixels[i + 2] != 0 {
        lit = true
        break
    }
    if !lit {
        try? FileManager.default.removeItem(atPath: outPath)
        fail("the image is all black (screen locked?); file deleted", 4)
    }
}

print("window \(window.id) bounds \(Int(window.width))x\(Int(window.height)) pt, image \(w)x\(h) px -> \(outPath)")
