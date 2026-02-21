//
//  HotKeyManager.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit
import Carbon

struct HotKeyCombo {
    let keyCode: UInt32
    let modifiers: UInt32

    static let togglePanel = HotKeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init(keyCombo: HotKeyCombo, handler: @escaping () -> Void) {
        self.handler = handler
        registerHotKey(combo: keyCombo)
    }

    func invalidate() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func registerHotKey(combo: HotKeyCombo) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x4D535044), id: 1)
        let eventTarget = GetApplicationEventTarget()

        RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            eventTarget,
            0,
            &hotKeyRef
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(eventTarget, { (_, eventRef, userData) -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handler()
            return noErr
        }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
    }
}
