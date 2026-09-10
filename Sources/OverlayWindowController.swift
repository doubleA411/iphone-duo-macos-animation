import Foundation
import AppKit

public final class OverlayWindowController: NSObject, NSWindowDelegate {
    public static let shared = OverlayWindowController()
    
    private var previewWindow: NSWindow?
    private var previewView: MetalFoldView?
    private var lastImage: CGImage?
    private var isSleeping = false
    private var window: NSWindow?
    private var metalView: MetalFoldView?
    private var captureGeneration = 0
    private var isCapturing = false
    private var wasZeroTurn = true
    
    public override init() {
        super.init()
        setupWindow()
        setupSleepObservers()
        
        // Connect intelligent hardware pre-arming
        LidSensor.shared.onPreArmCapture = { [weak self] in
            self?.captureScreenAsync()
        }
    }
    
    private func setupSleepObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Never redisplay a desktop snapshot from before sleep.
                if let image = ScreenCapture.shared.fetchWallpaperImage() ?? ScreenCapture.shared.fetchBundledDefaultImage() {
                    self?.lastImage = image
                    self?.metalView?.updateImage(image)
                }
                LidSensor.shared.resumeOpening()
                self?.isSleeping = false
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSleep()
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleSleep()
        }
    }
    
    private func handleSleep() {
        isSleeping = true
        lastImage = nil
        metalView?.clearImage()
        previewView?.clearImage()
        captureGeneration += 1
        isCapturing = false
        AppSettings.shared.isTestModeActive = false
        LidSensor.shared.resetMotion()
        stopOverlay()
        AppSettings.shared.isScreenCaptureDormant = true
    }
    
    private func setupWindow() {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        }) else { return }
        
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.alphaValue = 0.0
        
        let mtkView = MetalFoldView(frame: win.contentView?.bounds ?? screen.frame)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.isPaused = true
        win.contentView = mtkView
        
        self.window = win
        self.metalView = mtkView
        
        // One-time initial image load in background during app launch
        let initialGeneration = captureGeneration
        Task {
            if let img = await ScreenCapture.shared.fetchImage() {
                await MainActor.run {
                    guard initialGeneration == self.captureGeneration else { return }
                    self.lastImage = img
                    self.metalView?.updateImage(img)
                    self.previewView?.updateImage(img)
                    AppSettings.shared.lastCaptureDate = Date()
                    AppSettings.shared.isScreenCaptureDormant = true
                }
            }
        }
    }
    
    public func update(turn: Double, angle: Double) {
        guard !isSleeping else { stopOverlay(); return }
        if AppSettings.shared.isTestModeActive {
            stopOverlay()
            showPreview(turn: turn)
            return
        }
        closePreview()
        guard let win = self.window, let mv = self.metalView else { return }

        mv.currentTurn = Float(turn)
        
        // Only trigger when closing and turn > 0
        if turn > 0.0001 {
            if wasZeroTurn {
                wasZeroTurn = false
                // If pre-arm hasn't finished or was skipped, trigger emergency snapshot
                if AppSettings.shared.imageSourceMode == .liveCapture {
                    captureScreenAsync()
                }
            }
            
            mv.isPaused = false
            win.alphaValue = 1.0
            win.orderFrontRegardless()
        } else {
            wasZeroTurn = true
            win.alphaValue = 0.0
            mv.isPaused = true
        }
    }
    
    private func showPreview(turn: Double) {
        if previewWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 380),
                               styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            win.title = "Fold Preview — Esc to close · Auto-closes in 15 seconds"
            win.isReleasedWhenClosed = false
            win.delegate = self
            let view = MetalFoldView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
            view.autoresizingMask = [.width, .height]
            win.contentView = view
            if let lastImage { view.updateImage(lastImage) }
            previewView = view
            previewWindow = win
            win.center()
        }
        previewView?.currentTurn = Float(turn)
        previewView?.isPaused = false
        if previewWindow?.isVisible == false {
            previewWindow?.makeKeyAndOrderFront(nil)
            captureScreenAsync()
        }
    }

    public func closePreview() {
        previewView?.isPaused = true
        previewWindow?.orderOut(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        AppSettings.shared.isTestModeActive = false
    }

    public func stopOverlay() {
        wasZeroTurn = true
        window?.alphaValue = 0.0
        metalView?.isPaused = true
        metalView?.currentTurn = 0.0
    }
    
    public func captureScreenAsync() {
        guard !isCapturing else { return }
        isCapturing = true
        let generation = captureGeneration
        AppSettings.shared.isScreenCaptureDormant = false
        
        Task {
            if let image = await ScreenCapture.shared.fetchImage() {
                await MainActor.run {
                    guard generation == self.captureGeneration else { return }
                    self.lastImage = image
                    self.metalView?.updateImage(image)
                    self.previewView?.updateImage(image)
                    self.isCapturing = false
                    AppSettings.shared.lastCaptureDate = Date()
                    AppSettings.shared.isScreenCaptureDormant = true
                }
            } else {
                await MainActor.run {
                    guard generation == self.captureGeneration else { return }
                    self.isCapturing = false
                    AppSettings.shared.isScreenCaptureDormant = true
                }
            }
        }
    }
}
