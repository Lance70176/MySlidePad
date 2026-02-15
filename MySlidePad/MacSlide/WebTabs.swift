//
//  WebTabs.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import Combine
import Foundation
import WebKit

final class WebTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String
    @Published var url: URL
    @Published var needsExternalLogin: Bool = false
    var onURLChange: (() -> Void)?

    init(url: URL) {
        self.url = url
        self.title = url.host ?? url.absoluteString
        let configuration = WebViewConfigurationFactory.configured()
        self.webView = ZoomingWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        self.webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let title = webView.title, title.isEmpty == false {
            self.title = title
        }
        if let currentURL = webView.url {
            self.url = currentURL
            updateLoginRequirement(for: currentURL)
            onURLChange?()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let currentURL = webView.url {
            self.url = currentURL
            self.title = currentURL.host ?? currentURL.absoluteString
            updateLoginRequirement(for: currentURL)
            onURLChange?()
        }
    }

    private func updateLoginRequirement(for url: URL) {
        let host = url.host ?? ""
        needsExternalLogin = host.contains("accounts.google.com") || host.contains("accounts.googleusercontent.com")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        WebViewConfigurationFactory.installIMEGuard(into: configuration)
        return PopupWindowController.shared.openPopup(with: configuration, url: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canCreateDirectories = false
            panel.begin { response in
                if response == .OK {
                    completionHandler(panel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }
    }
}

enum WebViewConfigurationFactory {
    private static let imeGuardScript = """
    (function() {
        let composing = false;
        window.addEventListener('compositionstart', function() { composing = true; }, true);
        window.addEventListener('compositionend', function() { composing = false; }, true);
        window.addEventListener('keydown', function(event) {
            if (event.key === 'Enter' && (event.isComposing || composing || event.keyCode === 229)) {
                event.stopImmediatePropagation();
                event.stopPropagation();
            }
        }, true);
    })();
    """

    static func configured() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        installIMEGuard(into: configuration)
        return configuration
    }

    static func installIMEGuard(into configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        if controller.userScripts.contains(where: { $0.source == imeGuardScript }) {
            return
        }
        let script = WKUserScript(
            source: imeGuardScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(script)
    }
}

final class TabStore: ObservableObject {
    static let shared = TabStore()

    @Published var tabs: [WebTab]
    @Published var selectedID: UUID {
        didSet { persistState() }
    }

    private let defaultsKey = "MacSlide.TabState"
    private let selectedKey = "MacSlide.TabState.selected"
    private let favoritesKey = "MacSlide.Favorites"
    @Published var favorites: [String] {
        didSet { persistFavorites() }
    }

    private static let defaultFavorites: [String] = [
        "https://www.google.com/",
        "https://gemini.google.com/",
        "https://chatgpt.com/"
    ]

    private init() {
        if let restored = TabStore.restoreState(key: defaultsKey), restored.isEmpty == false {
            let restoredTabs = restored.compactMap { URL(string: $0) }.map { WebTab(url: $0) }
            if restoredTabs.isEmpty == false {
                self.tabs = restoredTabs
                let selectedIndex = UserDefaults.standard.integer(forKey: selectedKey)
                if selectedIndex < restoredTabs.count {
                    self.selectedID = restoredTabs[selectedIndex].id
                } else {
                    self.selectedID = restoredTabs.first?.id ?? UUID()
                }
            } else {
                let defaultTab = WebTab(url: URL(string: "https://www.apple.com")!)
                self.tabs = [defaultTab]
                self.selectedID = defaultTab.id
            }
        } else {
            let defaultTab = WebTab(url: URL(string: "https://www.apple.com")!)
            self.tabs = [defaultTab]
            self.selectedID = defaultTab.id
        }

        self.favorites = TabStore.restoreFavorites(key: favoritesKey) ?? TabStore.defaultFavorites

        tabs.forEach { tab in
            tab.onURLChange = { [weak self] in
                self?.persistState()
            }
        }
    }

    func addTab(url: URL) {
        let tab = WebTab(url: url)
        tab.onURLChange = { [weak self] in
            self?.persistState()
        }
        tabs.append(tab)
        selectedID = tab.id
        persistState()
    }

    func addBlankTab() {
        let tab = WebTab(url: URL(string: "about:blank")!)
        tab.onURLChange = { [weak self] in
            self?.persistState()
        }
        tabs.append(tab)
        selectedID = tab.id
        persistState()
    }

    func close(tab: WebTab) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == tab.id }
        if selectedID == tab.id, let first = tabs.first {
            selectedID = first.id
        }
        persistState()
    }

    func moveTab(from sourceID: UUID, to destinationID: UUID) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == sourceID }),
              let toIndex = tabs.firstIndex(where: { $0.id == destinationID }),
              fromIndex != toIndex else { return }
        let tab = tabs.remove(at: fromIndex)
        let adjustedIndex = fromIndex < toIndex ? max(toIndex - 1, 0) : toIndex
        tabs.insert(tab, at: adjustedIndex)
        selectedID = tab.id
        persistState()
    }

    func tab(for id: UUID) -> WebTab? {
        tabs.first { $0.id == id }
    }

    func openURL(_ raw: String, in tab: WebTab?) {
        guard let tab else { return }
        guard let url = normalizedURL(from: raw) else { return }
        tab.webView.load(URLRequest(url: url))
        tab.url = url
        tab.title = url.host ?? url.absoluteString
        tab.needsExternalLogin = (url.host?.contains("accounts.google.com") ?? false)
        tab.onURLChange?()
    }

    func openInChrome(url: URL?) {
        guard let url else { return }
        if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: config) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func addFavorite(_ raw: String) {
        guard let url = normalizedURL(from: raw) else { return }
        let value = url.absoluteString
        if favorites.contains(value) == false {
            favorites.append(value)
        }
    }

    func addFavorite(url: URL) {
        let value = url.absoluteString
        if favorites.contains(value) == false {
            favorites.append(value)
        }
    }

    func removeFavorite(_ raw: String) {
        favorites.removeAll { $0 == raw }
    }

    func resetFavorites() {
        favorites = TabStore.defaultFavorites
    }

    private func persistState() {
        let urls = tabs.map { $0.url.absoluteString }
        UserDefaults.standard.set(urls, forKey: defaultsKey)
        if let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            UserDefaults.standard.set(index, forKey: selectedKey)
        }
    }

    private static func restoreState(key: String) -> [String]? {
        UserDefaults.standard.array(forKey: key) as? [String]
    }

    private func persistFavorites() {
        UserDefaults.standard.set(favorites, forKey: favoritesKey)
    }

    private static func restoreFavorites(key: String) -> [String]? {
        UserDefaults.standard.array(forKey: key) as? [String]
    }

    private func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}
