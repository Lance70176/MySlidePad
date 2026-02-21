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
    private var entries: [(panel: NSPanel, webView: WKWebView, observer: NSObjectProtocol)] = []

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

        let popupView = PopupContentView(webView: webView, closePanel: { [weak panel] in
            panel?.close()
        })
        panel.contentView = NSHostingView(rootView: popupView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            webView.loadHTMLString("", baseURL: nil)
            if let idx = self?.entries.firstIndex(where: { $0.panel === panel }) {
                let entry = self?.entries.remove(at: idx)
                if let obs = entry?.observer {
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
        entries.append((panel: panel, webView: webView, observer: observer))

        return webView
    }

    func closePopup(containing webView: WKWebView) {
        guard let entry = entries.first(where: { $0.webView === webView }) else { return }
        entry.panel.close()
    }
}

private struct PopupContentView: View {
    let webView: WKWebView
    let closePanel: () -> Void
    @State private var addressText: String = ""
    @State private var showToolbar = true
    @State private var urlTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            if showToolbar {
                HStack(spacing: 6) {
                    // Address bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        TextField("Enter URL", text: $addressText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { navigateTo(addressText) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Open in main app
                    Button {
                        if let url = webView.url, url.absoluteString != "about:blank" {
                            TabStore.shared.addTab(url: url)
                            closePanel()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("Open in app panel")

                    // Open in browser
                    Button {
                        if let url = webView.url {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("Open in default browser")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
            }

            Divider()

            // WebView
            WebViewRepresentable(webView: webView)
        }
        .onAppear {
            updateAddress()
            startURLObservation()
        }
        .onDisappear {
            urlTimer?.invalidate()
            urlTimer = nil
        }
    }

    private func navigateTo(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if let parsed = URL(string: trimmed), parsed.scheme != nil {
            url = parsed
        } else {
            url = URL(string: "https://\(trimmed)")
        }
        if let url {
            webView.load(URLRequest(url: url))
        }
    }

    private func updateAddress() {
        if let url = webView.url, url.absoluteString != "about:blank" {
            addressText = url.absoluteString
        }
    }

    private func startURLObservation() {
        urlTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                updateAddress()
            }
        }
    }
}
