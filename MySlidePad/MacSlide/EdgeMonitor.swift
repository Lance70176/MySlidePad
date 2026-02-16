//
//  EdgeMonitor.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit

enum ScreenEdge {
    case left
    case right
    case top
    case bottom
}

final class EdgeMonitor {
    private let edge: ScreenEdge
    private let threshold: CGFloat
    private let cooldown: TimeInterval
    private let dwellTime: TimeInterval
    private let handler: () -> Void
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTrigger: Date?
    private var edgeEnteredAt: Date?
    private var lastScreenID: String?

    init(edge: ScreenEdge, threshold: CGFloat, cooldown: TimeInterval, dwellTime: TimeInterval = 0.15, handler: @escaping () -> Void) {
        self.edge = edge
        self.threshold = max(1, threshold)
        self.cooldown = max(0.1, cooldown)
        self.dwellTime = dwellTime
        self.handler = handler
        start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func start() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.pollMouseLocation()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.pollMouseLocation()
            return event
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.pollMouseLocation()
        }
    }

    private func pollMouseLocation() {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens

        guard let screen = screenContaining(mouse, in: screens) else {
            edgeEnteredAt = nil
            return
        }

        let currentID = screenID(for: screen)
        if currentID != lastScreenID {
            edgeEnteredAt = nil
            lastScreenID = currentID
        }

        if isEdgeHit(mouse: mouse, screen: screen) {
            if edgeEnteredAt == nil {
                edgeEnteredAt = Date()
            }
            if let entered = edgeEnteredAt,
               Date().timeIntervalSince(entered) >= dwellTime,
               shouldTrigger() {
                handler()
                lastTrigger = Date()
                edgeEnteredAt = nil
            }
        } else {
            edgeEnteredAt = nil
        }
    }

    private func screenContaining(_ point: CGPoint, in screens: [NSScreen]) -> NSScreen? {
        if let exact = screens.first(where: { $0.frame.contains(point) }) {
            return exact
        }
        // Mouse may be at the exact edge between screens; find the nearest screen.
        var best: NSScreen?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for screen in screens {
            let f = screen.frame
            let cx = min(max(point.x, f.minX), f.maxX)
            let cy = min(max(point.y, f.minY), f.maxY)
            let dist = hypot(point.x - cx, point.y - cy)
            if dist < bestDist {
                bestDist = dist
                best = screen
            }
        }
        return bestDist <= 2 ? best : nil
    }

    private func isEdgeHit(mouse: CGPoint, screen: NSScreen) -> Bool {
        let frame = screen.visibleFrame
        switch edge {
        case .left:
            guard !hasAdjacentScreen(on: .left, of: screen) else { return false }
            return mouse.x <= frame.minX + threshold
        case .right:
            guard !hasAdjacentScreen(on: .right, of: screen) else { return false }
            return mouse.x >= frame.maxX - threshold
        case .top:
            guard !hasAdjacentScreen(on: .top, of: screen) else { return false }
            return mouse.y >= frame.maxY - threshold
        case .bottom:
            guard !hasAdjacentScreen(on: .bottom, of: screen) else { return false }
            return mouse.y <= frame.minY + threshold
        }
    }

    /// Returns true if another screen is adjacent on the given side, meaning
    /// the edge is shared between two monitors rather than being a true outer edge.
    private func hasAdjacentScreen(on side: ScreenEdge, of screen: NSScreen) -> Bool {
        let f = screen.frame
        let tolerance: CGFloat = 1
        for other in NSScreen.screens where other !== screen {
            let o = other.frame
            switch side {
            case .right:
                // Another screen's left edge touches this screen's right edge
                if abs(o.minX - f.maxX) <= tolerance,
                   o.minY < f.maxY, o.maxY > f.minY { return true }
            case .left:
                if abs(f.minX - o.maxX) <= tolerance,
                   o.minY < f.maxY, o.maxY > f.minY { return true }
            case .top:
                if abs(o.minY - f.maxY) <= tolerance,
                   o.minX < f.maxX, o.maxX > f.minX { return true }
            case .bottom:
                if abs(f.minY - o.maxY) <= tolerance,
                   o.minX < f.maxX, o.maxX > f.minX { return true }
            }
        }
        return false
    }

    private func shouldTrigger() -> Bool {
        guard let lastTrigger else { return true }
        return Date().timeIntervalSince(lastTrigger) >= cooldown
    }

    private func screenID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
