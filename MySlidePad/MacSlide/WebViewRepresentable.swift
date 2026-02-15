//
//  WebViewRepresentable.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import AppKit
import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
    }
}

final class ZoomingWebView: WKWebView {
    private let zoomStep: Double = 0.1
    private let minZoom: Double = 0.5
    private let maxZoom: Double = 3.0

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 24: // '=' / '+'
            pageZoom = min(pageZoom + zoomStep, maxZoom)
        case 27: // '-' / '_'
            pageZoom = max(pageZoom - zoomStep, minZoom)
        case 29: // '0'
            pageZoom = 1.0
        case 15: // 'R'
            if event.modifierFlags.contains(.shift) {
                reloadFromOrigin()
            } else {
                reload()
            }
        default:
            super.keyDown(with: event)
        }
    }
}
