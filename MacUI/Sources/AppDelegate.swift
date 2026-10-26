import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var overlayWindow: SubtitleOverlayWindow!
    var liveWindow: NSWindow?
    var historyWindow: NSWindow?
    
    // State logic
    let wsManager = WebSocketManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start python backend process
        BackendManager.shared.start()
        
        // Setup popover view
        let settingsView = SettingsView()
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 640)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: settingsView)
        
        // Setup status item (Menu bar icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "SonioxTrans")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        setupOverlayWindow()
        
        // Setup quit handler
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            BackendManager.shared.stop()
        }
        NotificationCenter.default.addObserver(forName: .showConversationHistory,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.showHistoryWindow()
        }
        NotificationCenter.default.addObserver(forName: .subtitleDisplayModeChanged,
                                               object: nil, queue: .main) { [weak self] notification in
            self?.applyDisplayMode(notification.object as? String)
        }
        NotificationCenter.default.addObserver(forName: .showLiveSubtitleWindow,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.showLiveWindow()
        }
        applyDisplayMode(nil)
    }

    func showHistoryWindow() {
        if historyWindow == nil {
            let controller = NSHostingController(rootView: HistoryView())
            let window = NSWindow(contentViewController: controller)
            window.title = "SonioxTrans 对话记录"
            window.setContentSize(NSSize(width: 980, height: 620))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            historyWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    func showLiveWindow() {
        if liveWindow == nil {
            let controller = NSHostingController(rootView: LiveTranscriptView(wsManager: wsManager))
            let window = NSWindow(contentViewController: controller)
            window.title = "SonioxTrans 实时字幕"
            window.setContentSize(NSSize(width: 1050, height: 620))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            liveWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        liveWindow?.makeKeyAndOrderFront(nil)
    }

    func applyDisplayMode(_ requestedMode: String?) {
        let mode = requestedMode ?? UserDefaults.standard.string(forKey: "subtitleDisplayMode") ?? "overlay"
        if mode == "window" {
            overlayWindow?.orderOut(nil)
            showLiveWindow()
        } else {
            liveWindow?.orderOut(nil)
            overlayWindow?.orderFrontRegardless()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        BackendManager.shared.stop()
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    func makeOverlayPanel(rect: NSRect) -> SubtitleOverlayWindow {
        let panel = SubtitleOverlayWindow(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = wsManager.isUIUnlocked
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
    
    func setupOverlayWindow() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let windowW = min(CGFloat(1080), visible.width - 80)
        // This is the maximum visible conversation area. Older rows stay
        // available through the shared vertical scroller.
        let windowH: CGFloat = 380
        let centerX = visible.midX - windowW / 2
        let preferredY = visible.minY + 130
        let y = min(preferredY, visible.maxY - windowH - 40)
        let rect = NSRect(x: centerX, y: y, width: windowW, height: windowH)

        overlayWindow = makeOverlayPanel(rect: rect)
        let hosting = NSHostingView(rootView: MergedOverlayView(wsManager: wsManager))
        hosting.frame = overlayWindow.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        overlayWindow.contentView?.addSubview(hosting)
    }
}

// Custom Panel subclass
class SubtitleOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}
