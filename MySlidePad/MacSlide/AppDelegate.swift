//
//  AppDelegate.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = PanelController()
    private var hotKeyManager: HotKeyManager?
    private var edgeMonitor: EdgeMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        panelController.prepare()

        hotKeyManager = HotKeyManager(keyCombo: .togglePanel) { [weak self] in
            self?.panelController.toggle()
        }

        edgeMonitor = EdgeMonitor(edge: .right, threshold: 2, cooldown: 0.6) { [weak self] in
            self?.panelController.showIfHidden()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.invalidate()
        edgeMonitor?.stop()
    }

    func setInteractionEnabled(_ enabled: Bool) {
        panelController.setInteractionEnabled(enabled)
    }
}
