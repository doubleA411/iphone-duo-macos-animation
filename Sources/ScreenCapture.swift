import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

public final class ScreenCapture {
    public static let shared = ScreenCapture()
    
    private init() {}
    
    /// Fast synchronous preflight
    public func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Comprehensive async verification using both CoreGraphics and ScreenCaptureKit
    public func verifyPermissionAsync() async -> Bool {
        return await captureLiveScreen(probe: true) != nil
    }
    
    /// Request screen recording permission from macOS
    @discardableResult
    public func requestPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// Open System Settings directly to Privacy & Security -> Screen Recording
    public func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Relaunch application to pick up updated TCC permissions
    public func relaunchApp() {
        let appUrl = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: appUrl, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    /// Capture the screen or load appropriate image based on settings
    public func fetchImage() async -> CGImage? {
        let settings = AppSettings.shared
        
        switch settings.imageSourceMode {
        case .liveCapture:
            if let img = await captureLiveScreen() {
                return img
            }
            // Fallback if permission not granted or capture failed
            return fetchWallpaperImage() ?? fetchBundledDefaultImage()
            
        case .desktopWallpaper:
            return fetchWallpaperImage() ?? fetchBundledDefaultImage()
            
        case .bundledArtwork:
            return fetchBundledDefaultImage()
            
        case .customImage:
            if !settings.customImagePath.isEmpty,
               let image = NSImage(contentsOfFile: settings.customImagePath),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
            return fetchBundledDefaultImage()
        }
    }
    
    /// Live display capture using ScreenCaptureKit
    public func captureLiveScreen(probe: Bool = false) async -> CGImage? {
        do {
            let content: SCShareableContent
            if #available(macOS 14.4, *) {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } else {
                content = try await SCShareableContent.current
            }
            guard let display = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) else { return nil }
            
            // Exclude our own app's windows
            let currentAppPID = NSRunningApplication.current.processIdentifier
            let excludedWindows = content.windows.filter { $0.owningApplication?.processID == currentAppPID }
            
            let scale = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID })?.backingScaleFactor ?? 2.0
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()
            config.width = probe ? 2 : Int(Double(display.width) * scale)
            config.height = probe ? 2 : Int(Double(display.height) * scale)
            config.showsCursor = true
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return image
        } catch {
            print("[ScreenCapture] ScreenCaptureKit error: \(error)")
            return nil
        }
    }
    
    /// Get user's current desktop wallpaper
    public func fetchWallpaperImage() -> CGImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    /// Fallback to the bundled default.png artwork
    public func fetchBundledDefaultImage() -> CGImage? {
        if let bundleUrl = Bundle.main.url(forResource: "default", withExtension: "png"),
           let img = NSImage(contentsOf: bundleUrl) {
            return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        
        let fallbackPaths = [
            Bundle.main.bundlePath + "/Contents/Resources/default.png",
            Bundle.main.bundlePath + "/Resources/default.png",
            CommandLine.arguments[0].split(separator: "/").dropLast().joined(separator: "/") + "/Resources/default.png",
        ]
        for path in fallbackPaths {
            if let img = NSImage(contentsOfFile: path),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
        }
        return nil
    }
}
