//
//  PopupWindowController.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit
import SwiftUI
import WebKit

final class PopupWindowController {
    static let shared = PopupWindowController()
    private var panels: [NSPanel] = []

    func openPopup(with configuration: WKWebViewConfiguration, url: URL?) -> WKWebView {
        let webView = ZoomingWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.contentView = NSHostingView(rootView: WebViewRepresentable(webView: webView))
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        panels.append(panel)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panels.removeAll { $0 === panel }
        }

        if let url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }
}
