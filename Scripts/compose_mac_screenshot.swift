// Lays a Mac window screenshot onto a backdrop, the way Mac App Store listings
// present an app: the window floating, corners rounded, a soft shadow under it.
//
// Compiled and driven by Scripts/screenshots.sh. A UI test can only photograph
// the window's own rectangle — no shadow, no desktop, square corners — so the
// presentation is drawn here instead.
//
//   compose_mac_screenshot <window.png> <output.png> <width> <height> [backdrop.png]
//   compose_mac_screenshot --window-id <bundle id>
//
// Without a backdrop image, the background is a deep sea gradient in the app's
// own colours. Drop a file at fastlane/screenshots/mac/backdrop.png to use your
// own; it is scaled to fill.
//
// `--window-id` prints the id of the app's window, which is what
// `screencapture -l` wants. The script photographs the window that way rather
// than from inside the UI test, because a UI test flattens the window onto an
// opaque rectangle — its rounded corners come out filled in black, and no
// amount of rounding them again hides that. `screencapture` keeps the alpha.

import AppKit
import CoreGraphics
import Foundation

struct Failure: Error { let message: String }

/// The id of the frontmost on-screen window belonging to the given app.
func windowID(bundleIdentifier: String) throws -> CGWindowID {
    let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    guard let pid = application?.processIdentifier else {
        throw Failure(message: "\(bundleIdentifier) is not running")
    }
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        throw Failure(message: "could not list the windows")
    }
    for window in windows {
        guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
              let identifier = window[kCGWindowNumber as String] as? CGWindowID,
              let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let height = bounds["Height"] as? Double, height > 200 else { continue }
        return identifier
    }
    throw Failure(message: "\(bundleIdentifier) has no window on screen")
}

func loadImage(_ path: String) throws -> CGImage {
    guard let data = NSData(contentsOfFile: path),
          let source = CGImageSourceCreateWithData(data, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw Failure(message: "cannot read image at \(path)")
    }
    return image
}

func write(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        throw Failure(message: "cannot write to \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure(message: "could not encode \(path)")
    }
}

/// Fills the canvas with the backdrop image, cropping rather than squashing it.
func drawBackdrop(_ context: CGContext, image: CGImage, canvas: CGRect) {
    let scale = max(canvas.width / CGFloat(image.width), canvas.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    context.draw(image, in: CGRect(
        x: canvas.midX - size.width / 2,
        y: canvas.midY - size.height / 2,
        width: size.width,
        height: size.height
    ))
}

/// The default backdrop: the night sea the app icon is painted in.
func drawGradient(_ context: CGContext, canvas: CGRect) {
    let colors = [
        CGColor(red: 0.04, green: 0.11, blue: 0.24, alpha: 1),
        CGColor(red: 0.10, green: 0.28, blue: 0.48, alpha: 1),
        CGColor(red: 0.18, green: 0.47, blue: 0.66, alpha: 1)
    ] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.55, 1]
    ) else { return }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: canvas.midX, y: canvas.maxY),
        end: CGPoint(x: canvas.midX, y: canvas.minY),
        options: []
    )
}

let arguments = CommandLine.arguments

if arguments.count == 3, arguments[1] == "--window-id" {
    do {
        print(try windowID(bundleIdentifier: arguments[2]))
        exit(0)
    } catch let failure as Failure {
        FileHandle.standardError.write(Data("error: \(failure.message)\n".utf8))
        exit(1)
    }
}

guard arguments.count >= 5, let width = Int(arguments[3]), let height = Int(arguments[4]) else {
    FileHandle.standardError.write(
        Data("usage: compose_mac_screenshot <window.png> <out.png> <width> <height> [backdrop.png]\n".utf8)
    )
    exit(2)
}

do {
    let window = try loadImage(arguments[1])
    let canvas = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        // No alpha: the App Store rejects screenshots that carry one.
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw Failure(message: "could not create the canvas")
    }

    if arguments.count >= 6, FileManager.default.fileExists(atPath: arguments[5]) {
        drawBackdrop(context, image: try loadImage(arguments[5]), canvas: canvas)
    } else {
        drawGradient(context, canvas: canvas)
    }

    // The window image comes from `screencapture`, so it arrives the way macOS
    // draws it: rounded corners cut out of the alpha, and the system's own
    // drop shadow — soft, semi-transparent — already around it. Compositing it
    // over the backdrop is therefore just a draw: the shadow blends with the
    // wallpaper exactly as it would on a real desktop.
    let margin = canvas.width * 0.06
    let available = canvas.insetBy(dx: margin, dy: margin)
    let scale = min(
        available.width / CGFloat(window.width),
        available.height / CGFloat(window.height)
    )
    let size = CGSize(width: CGFloat(window.width) * scale, height: CGFloat(window.height) * scale)
    context.draw(window, in: CGRect(
        x: canvas.midX - size.width / 2,
        y: canvas.midY - size.height / 2,
        width: size.width,
        height: size.height
    ))

    guard let composed = context.makeImage() else {
        throw Failure(message: "could not render the composition")
    }
    try write(composed, to: arguments[2])
} catch let failure as Failure {
    FileHandle.standardError.write(Data("error: \(failure.message)\n".utf8))
    exit(1)
}
