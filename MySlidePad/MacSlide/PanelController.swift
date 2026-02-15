//
//  PanelController.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit
import QuartzCore
import SwiftUI

final class PanelController {
    private enum DefaultsKey {
        static let panelLayoutPrefix = "MacSlide.PanelLayout."
        static let lastScreenID = "MacSlide.LastScreenID"
    }

    private var panel: NSPanel?
    private var isVisible = false
    private let panelWidth: CGFloat = 800
    private let peekOffset: CGFloat = 0
    private let autoHideDelay: TimeInterval = 0.5
    private var panelSize: CGSize?
    private var autoHideTimer: Timer?
    private var outsideSince: Date?
    private var mouseMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var isInteractionEnabled = false

    func prepare() {
        if panel != nil { return }
        let panel = makePanel()
        self.panel = panel
        panelSize = panel.frame.size
        position(panel: panel, visible: false, animate: false)
        observeResize(for: panel)
        observeMove(for: panel)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func showIfHidden() {
        guard isVisible == false else { return }
        show()
    }

    func show() {
        guard let panel else { return }
        let target = screenForMouse() ?? preferredScreenFromDefaults()
        position(panel: panel, visible: false, animate: false, preferredScreen: target)
        panel.orderFrontRegardless()
        position(panel: panel, visible: true, animate: true, preferredScreen: target)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
        startMouseMonitoring()
    }

    func hide() {
        guard let panel else { return }
        if isInteractionEnabled {
            setInteractionEnabled(false)
        }
        position(panel: panel, visible: false, animate: true, preferredScreen: panel.screen) { [weak panel] in
            panel?.orderOut(nil)
        }
        isVisible = false
        stopMouseMonitoring()
    }

    private func makePanel() -> NSPanel {
        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable]
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: true
        )

        panel.isMovableByWindowBackground = true
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = PanelView()
        panel.contentView = NSHostingView(rootView: view)
        panel.contentView?.wantsLayer = true
        panel.minSize = CGSize(width: 320, height: 360)

        return panel
    }

    func setInteractionEnabled(_ enabled: Bool) {
        guard let panel else { return }
        isInteractionEnabled = enabled
        if enabled {
            panel.becomesKeyOnlyIfNeeded = false
            NSApplication.shared.setActivationPolicy(.regular)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.becomesKeyOnlyIfNeeded = true
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    private func position(panel: NSPanel, visible: Bool, animate: Bool, preferredScreen: NSScreen? = nil, completion: (() -> Void)? = nil) {
        guard let screen = preferredScreen ?? screenForMouse() ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let size = resolvedPanelSize(on: screen)
        let xVisible = screen.visibleFrame.maxX - size.width
        let xHidden = screen.visibleFrame.maxX - peekOffset

        let targetX = visible ? xVisible : xHidden
        let y = resolvedPanelY(on: screen, size: size)
        let frame = CGRect(x: targetX, y: y, width: size.width, height: size.height)

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: {
                completion?()
            }
        } else {
            panel.setFrame(frame, display: true)
            completion?()
        }
    }

    private func screenForMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func resolvedPanelSize(on screen: NSScreen) -> CGSize {
        let saved = loadPanelLayout(for: screen)?.size
        let current = saved ?? panelSize ?? CGSize(width: panelWidth, height: 900)
        let minWidth = panel?.minSize.width ?? 320
        let minHeight = panel?.minSize.height ?? 360
        let maxHeight = screen.visibleFrame.height
        let width = max(current.width, minWidth)
        let height = min(max(current.height, minHeight), maxHeight)
        return CGSize(width: width, height: height)
    }

    private func observeResize(for panel: NSPanel) {
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.recordPanelLayout(for: panel)
        }
    }

    private func observeMove(for panel: NSPanel) {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.recordPanelLayout(for: panel)
        }
    }

    private func recordPanelLayout(for panel: NSPanel) {
        guard let screen = panel.screen ?? screenForMouse() else { return }
        let size = panel.frame.size
        panelSize = size
        let yRatio = panelYRatio(panelFrame: panel.frame, visibleFrame: screen.visibleFrame)
        savePanelLayout(size: size, yRatio: yRatio, for: screen)
        saveLastScreen(screen)
    }

    private func resolvedPanelY(on screen: NSScreen, size: CGSize) -> CGFloat {
        if let layout = loadPanelLayout(for: screen) {
            let ratio = min(max(layout.yRatio, 0), 1)
            let midY = screen.visibleFrame.minY + screen.visibleFrame.height * ratio
            return midY - size.height / 2
        }
        return screen.visibleFrame.minY + (screen.visibleFrame.height - size.height) / 2
    }

    private func panelYRatio(panelFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
        let midY = panelFrame.midY
        return (midY - visibleFrame.minY) / max(visibleFrame.height, 1)
    }

    private func screenID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName.replacingOccurrences(of: " ", with: "_")
    }

    private func screenByID(_ id: String) -> NSScreen? {
        NSScreen.screens.first { screenID(for: $0) == id }
    }

    private func layoutKey(_ screen: NSScreen, suffix: String) -> String {
        "\(DefaultsKey.panelLayoutPrefix)\(screenID(for: screen)).\(suffix)"
    }

    private func loadPanelLayout(for screen: NSScreen) -> (size: CGSize, yRatio: CGFloat)? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: layoutKey(screen, suffix: "width"))
        let height = defaults.double(forKey: layoutKey(screen, suffix: "height"))
        let yRatio = defaults.double(forKey: layoutKey(screen, suffix: "yRatio"))
        guard width > 0, height > 0 else { return nil }
        return (size: CGSize(width: width, height: height), yRatio: CGFloat(yRatio))
    }

    private func savePanelLayout(size: CGSize, yRatio: CGFloat, for screen: NSScreen) {
        let defaults = UserDefaults.standard
        defaults.set(size.width, forKey: layoutKey(screen, suffix: "width"))
        defaults.set(size.height, forKey: layoutKey(screen, suffix: "height"))
        defaults.set(yRatio, forKey: layoutKey(screen, suffix: "yRatio"))
    }

    private func saveLastScreen(_ screen: NSScreen) {
        UserDefaults.standard.set(screenID(for: screen), forKey: DefaultsKey.lastScreenID)
    }

    private func preferredScreenFromDefaults() -> NSScreen? {
        guard let id = UserDefaults.standard.string(forKey: DefaultsKey.lastScreenID) else { return nil }
        return screenByID(id)
    }

    private func startMouseMonitoring() {
        if mouseMonitor != nil { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.evaluateAutoHide()
        }

        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.evaluateAutoHide()
        }
    }

    private func stopMouseMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        outsideSince = nil
    }

    private func evaluateAutoHide() {
        guard isVisible, let panel else { return }
        let mouse = NSEvent.mouseLocation
        let inside = panel.frame.contains(mouse)

        if inside {
            outsideSince = nil
            return
        }

        if outsideSince == nil {
            outsideSince = Date()
        }

        if let outsideSince, Date().timeIntervalSince(outsideSince) >= autoHideDelay {
            hide()
        }
    }
}
