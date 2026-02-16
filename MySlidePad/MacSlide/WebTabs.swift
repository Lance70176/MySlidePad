//
//  WebTabs.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import Combine
import Foundation
import WebKit

final class WebTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String
    @Published var url: URL
    @Published var faviconURL: URL?
    @Published var needsExternalLogin: Bool = false
    var onURLChange: (() -> Void)?

    private static let forceClearCacheKey = "MacSlide.ForceClearCache"
    static var forceClearCache: Bool {
        get { UserDefaults.standard.bool(forKey: forceClearCacheKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceClearCacheKey) }
    }

    init(url: URL) {
        self.url = url
        self.title = url.host ?? url.absoluteString
        let configuration = WebViewConfigurationFactory.configured()
        self.webView = ZoomingWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        self.webView.configuration.userContentController.add(self, name: "blobDownload")
        self.webView.configuration.userContentController.add(self, name: "geminiCategories")
        self.webView.configuration.userContentController.add(self, name: "chatgptCategories")
        WebViewConfigurationFactory.installBlobDownloadHook(into: self.webView.configuration)
        WebViewConfigurationFactory.installGeminiSidebarScript(into: self.webView.configuration)
        WebViewConfigurationFactory.installChatGPTSidebarScript(into: self.webView.configuration)
        self.webView.load(URLRequest(url: url))
    }

    private static let geminiCategoriesKey = "MacSlide.GeminiCategories"
    private static let geminiCategoryRulesKey = "MacSlide.GeminiCategoryRules"
    private static let chatgptCategoriesKey = "MacSlide.ChatGPTCategories"
    private static let chatgptCategoryRulesKey = "MacSlide.ChatGPTCategoryRules"

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "geminiCategories" {
            handleGeminiCategories(message)
            return
        }
        if message.name == "chatgptCategories" {
            handleChatGPTCategories(message)
            return
        }

        NSLog("[MacSlide] blobDownload message received: %@", String(describing: type(of: message.body)))
        guard message.name == "blobDownload",
              let dict = message.body as? [String: String],
              let base64 = dict["data"],
              let filename = dict["filename"],
              let data = Data(base64Encoded: base64) else {
            NSLog("[MacSlide] blobDownload: failed to parse message")
            return
        }
        NSLog("[MacSlide] blobDownload: saving %@ (%d bytes)", filename, data.count)

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.level = .floating + 1
        NSApp.activate(ignoringOtherApps: true)
        let result = savePanel.runModal()
        if result == .OK, let url = savePanel.url {
            try? data.write(to: url)
            NSLog("[MacSlide] blobDownload: saved to %@", url.path)
        }
    }

    private func handleGeminiCategories(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else {
            NSLog("[MacSlide] geminiCategories: invalid message")
            return
        }

        switch action {
        case "save":
            if let data = dict["data"] as? [String: String] {
                UserDefaults.standard.set(data, forKey: WebTab.geminiCategoriesKey)
                NSLog("[MacSlide] geminiCategories: saved %d mappings", data.count)
            }
        case "load":
            let categories = UserDefaults.standard.dictionary(forKey: WebTab.geminiCategoriesKey) as? [String: String] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: categories)) ?? Data()
            let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
            webView.evaluateJavaScript("window.__geminiLoadCategories && window.__geminiLoadCategories(\(jsonStr))")
        case "saveRules":
            if let data = dict["data"] as? [String: [String]] {
                UserDefaults.standard.set(data, forKey: WebTab.geminiCategoryRulesKey)
                NSLog("[MacSlide] geminiCategories: saved rules")
            }
        case "loadRules":
            let rules = UserDefaults.standard.dictionary(forKey: WebTab.geminiCategoryRulesKey) as? [String: [String]] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data()
            let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
            webView.evaluateJavaScript("window.__geminiLoadRules && window.__geminiLoadRules(\(jsonStr))")
        default:
            NSLog("[MacSlide] geminiCategories: unknown action %@", action)
        }
    }

    private func handleChatGPTCategories(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else {
            NSLog("[MacSlide] chatgptCategories: invalid message")
            return
        }

        switch action {
        case "save":
            if let data = dict["data"] as? [String: String] {
                UserDefaults.standard.set(data, forKey: WebTab.chatgptCategoriesKey)
                NSLog("[MacSlide] chatgptCategories: saved %d mappings", data.count)
            }
        case "load":
            let categories = UserDefaults.standard.dictionary(forKey: WebTab.chatgptCategoriesKey) as? [String: String] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: categories)) ?? Data()
            let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
            webView.evaluateJavaScript("window.__chatgptLoadCategories && window.__chatgptLoadCategories(\(jsonStr))")
        case "saveRules":
            if let data = dict["data"] as? [String: [String]] {
                UserDefaults.standard.set(data, forKey: WebTab.chatgptCategoryRulesKey)
                NSLog("[MacSlide] chatgptCategories: saved rules")
            }
        case "loadRules":
            let rules = UserDefaults.standard.dictionary(forKey: WebTab.chatgptCategoryRulesKey) as? [String: [String]] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data()
            let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
            webView.evaluateJavaScript("window.__chatgptLoadRules && window.__chatgptLoadRules(\(jsonStr))")
        case "debug":
            if let msg = dict["msg"] as? String {
                NSLog("[MacSlide][CGPT-Debug] %@", msg)
            }
        default:
            NSLog("[MacSlide] chatgptCategories: unknown action %@", action)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if WebTab.forceClearCache {
            let dataStore = webView.configuration.websiteDataStore
            let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {}
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let title = webView.title, title.isEmpty == false {
            self.title = title
        }
        if let currentURL = webView.url {
            self.url = currentURL
            updateLoginRequirement(for: currentURL)
            onURLChange?()
            extractFavicon(from: webView, pageURL: currentURL)
        }
    }

    private func extractFavicon(from webView: WKWebView, pageURL: URL) {
        let js = """
        (function() {
            var icons = document.querySelectorAll('link[rel*="icon"]');
            var best = null;
            var bestSize = 0;
            for (var i = 0; i < icons.length; i++) {
                var href = icons[i].getAttribute('href');
                if (!href) continue;
                var sizes = icons[i].getAttribute('sizes') || '';
                var size = 0;
                var m = sizes.match(/(\\d+)/);
                if (m) size = parseInt(m[1]);
                if (size > bestSize || !best) { best = href; bestSize = size; }
            }
            return best;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let href = result as? String, !href.isEmpty else { return }
            let resolved: URL?
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                resolved = URL(string: href)
            } else if href.hasPrefix("//") {
                resolved = URL(string: "https:" + href)
            } else {
                resolved = URL(string: href, relativeTo: pageURL)?.absoluteURL
            }
            if let url = resolved {
                DispatchQueue.main.async { self.faviconURL = url }
            }
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

    // MARK: - Download handling

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        NSLog("[MacSlide] navigationAction: url=%@ shouldDownload=%d", navigationAction.request.url?.absoluteString ?? "nil", navigationAction.shouldPerformDownload ? 1 : 0)
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType ?? "unknown"
        NSLog("[MacSlide] navigationResponse: url=%@ mime=%@ canShow=%d", navigationResponse.response.url?.absoluteString ?? "nil", mime, navigationResponse.canShowMIMEType ? 1 : 0)
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        NSLog("[MacSlide] navigationAction didBecome download: %@", download.originalRequest?.url?.absoluteString ?? "nil")
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        NSLog("[MacSlide] navigationResponse didBecome download: %@", download.originalRequest?.url?.absoluteString ?? "nil")
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        NSLog("[MacSlide] decideDestination: filename=%@ url=%@", suggestedFilename, response.url?.absoluteString ?? "nil")
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        savePanel.level = .floating + 1
        NSApp.activate(ignoringOtherApps: true)
        let result = savePanel.runModal()
        if result == .OK, let url = savePanel.url {
            try? FileManager.default.removeItem(at: url)
            completionHandler(url)
        } else {
            completionHandler(nil)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    }

    func downloadDidFinish(_ download: WKDownload) {
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

    private static let blobDownloadScript = """
    (function() {
        if (window.__blobDownloadHooked) return;
        window.__blobDownloadHooked = true;
        const origCreate = URL.createObjectURL;
        const blobMap = new Map();
        URL.createObjectURL = function(obj) {
            const url = origCreate.call(URL, obj);
            if (obj instanceof Blob) blobMap.set(url, obj);
            return url;
        };
        const origRevoke = URL.revokeObjectURL;
        URL.revokeObjectURL = function(url) {
            blobMap.delete(url);
            return origRevoke.call(URL, url);
        };
        const origClick = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function() {
            const href = this.href || '';
            if (href.startsWith('blob:') || this.hasAttribute('download')) {
                const blob = blobMap.get(href);
                if (blob) {
                    const filename = this.download || 'download';
                    const reader = new FileReader();
                    reader.onload = function() {
                        const base64 = reader.result.split(',')[1];
                        window.webkit.messageHandlers.blobDownload.postMessage({data: base64, filename: filename});
                    };
                    reader.readAsDataURL(blob);
                    return;
                }
            }
            return origClick.call(this);
        };
    })();
    """

    // MARK: - Gemini Sidebar Category Script

    private static let geminiSidebarScript = """
    (function() {
        if (window.__geminiSidebarInjected) return;
        window.__geminiSidebarInjected = true;
        if (!location.hostname.includes('gemini.google.com')) return;

        const DEFAULT_RULES = {
            "程式": ["code","API","JSON","bug","程式","開發","debug","python","javascript","模型","swift","css","html","react","node"],
            "工作": ["工作","報告","會議","專案","企劃","簡報","email"],
            "學習": ["學習","教學","筆記","研究","分析","論文"],
            "遊戲": ["遊戲","攻略","博德之門","game","steam"],
            "其他": []
        };
        let categoryRules = JSON.parse(JSON.stringify(DEFAULT_RULES));
        let manualCategories = {};
        const ALL_LABEL = "全部";
        let currentFilter = ALL_LABEL;
        let contextMenu = null;

        // ── Swift bridge ──
        function loadFromSwift() {
            try {
                window.webkit.messageHandlers.geminiCategories.postMessage({action:"load"});
                window.webkit.messageHandlers.geminiCategories.postMessage({action:"loadRules"});
            } catch(e){}
        }
        window.__geminiLoadCategories = function(d) {
            if (d && typeof d === 'object') { manualCategories = d; applyFilter(); }
        };
        window.__geminiLoadRules = function(d) {
            if (d && typeof d === 'object' && Object.keys(d).length > 0) {
                categoryRules = d;
                if (!categoryRules["其他"]) categoryRules["其他"] = [];
                rebuildBar(); applyFilter();
            }
        };
        function saveToSwift() {
            try { window.webkit.messageHandlers.geminiCategories.postMessage({action:"save",data:manualCategories}); } catch(e){}
        }
        function saveRulesToSwift() {
            try { window.webkit.messageHandlers.geminiCategories.postMessage({action:"saveRules",data:categoryRules}); } catch(e){}
        }

        function classifyTitle(title) {
            if (manualCategories[title]) return manualCategories[title];
            const lower = title.toLowerCase();
            for (const [cat, keywords] of Object.entries(categoryRules)) {
                if (cat === "其他") continue;
                for (const kw of keywords) {
                    if (lower.includes(kw.toLowerCase())) return cat;
                }
            }
            return "其他";
        }
        // classify without manual override
        function autoClassifyTitle(title) {
            const lower = title.toLowerCase();
            for (const [cat, keywords] of Object.entries(categoryRules)) {
                if (cat === "其他") continue;
                for (const kw of keywords) {
                    if (lower.includes(kw.toLowerCase())) return cat;
                }
            }
            return "其他";
        }

        // ── CSS ──
        const style = document.createElement('style');
        style.textContent = `
            #gsc-category-bar {
                display:flex; gap:6px; padding:6px 16px 8px 16px;
                overflow-x:auto; scrollbar-width:none; flex-wrap:wrap; align-items:center;
            }
            #gsc-category-bar::-webkit-scrollbar{display:none}
            .gsc-chip {
                padding:3px 10px; border-radius:14px; font-size:12px;
                cursor:pointer; white-space:nowrap;
                background:var(--gsc-chip-bg,rgba(0,0,0,0.06));
                color:var(--gsc-chip-fg,rgba(0,0,0,0.55));
                border:1px solid var(--gsc-chip-border,rgba(0,0,0,0.08));
                transition:all .15s; user-select:none; line-height:1.5;
                font-family:'Google Sans',Roboto,Arial,sans-serif;
            }
            .gsc-chip:hover{background:var(--gsc-chip-hover-bg,rgba(0,0,0,0.1));color:var(--gsc-chip-hover-fg,rgba(0,0,0,0.8))}
            .gsc-chip.active{background:#4285f4;color:#fff;border-color:#4285f4}
            .gsc-chip.gsc-manage{
                background:transparent; border:1px dashed var(--gsc-chip-border,rgba(0,0,0,0.15));
                color:var(--gsc-chip-fg,rgba(0,0,0,0.4)); font-size:14px; padding:2px 8px;
            }
            .gsc-chip.gsc-manage:hover{color:var(--gsc-chip-hover-fg,rgba(0,0,0,0.7));border-style:solid}
            .gsc-tools-group{display:flex;gap:6px;margin-left:auto}
            .gsc-chip.gsc-tool{
                background:transparent; border:1px dashed var(--gsc-chip-border,rgba(0,0,0,0.15));
                color:var(--gsc-chip-fg,rgba(0,0,0,0.4)); font-size:11px; padding:3px 8px;
            }
            .gsc-chip.gsc-tool:hover{color:#4285f4;border-color:#4285f4}
            @keyframes gscSpin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
            .gsc-spinner{display:inline-block;width:14px;height:14px;border:2px solid rgba(0,0,0,0.15);border-top-color:#4285f4;border-radius:50%;animation:gscSpin .6s linear infinite;vertical-align:middle;margin-right:6px}
            /* Popup context menu */
            .gsc-ctx-menu{
                position:fixed; background:var(--gsc-menu-bg,#fff);
                border:1px solid var(--gsc-menu-border,rgba(0,0,0,0.12));
                border-radius:8px; padding:4px 0; min-width:160px; z-index:999999;
                box-shadow:0 4px 16px rgba(0,0,0,0.18);
                font-family:'Google Sans',Roboto,Arial,sans-serif;
            }
            .gsc-ctx-item{
                padding:8px 16px; font-size:13px; color:var(--gsc-menu-fg,rgba(0,0,0,0.8));
                cursor:pointer; display:flex; align-items:center; gap:8px;
            }
            .gsc-ctx-item:hover{background:var(--gsc-menu-hover,rgba(0,0,0,0.05))}
            .gsc-ctx-header{
                padding:6px 16px 4px; font-size:11px; color:var(--gsc-menu-dim,rgba(0,0,0,0.4));
                pointer-events:none; font-weight:500;
            }
            .gsc-ctx-divider{height:1px;background:var(--gsc-menu-border,rgba(0,0,0,0.08));margin:4px 0}
            .gsc-hidden{display:none!important}
            /* ── Modal overlay ── */
            .gsc-overlay{
                position:fixed;inset:0;background:rgba(0,0,0,0.45);z-index:999998;
                display:flex;align-items:center;justify-content:center;
            }
            .gsc-modal{
                background:var(--gsc-menu-bg,#fff);border-radius:12px;padding:20px 24px;
                min-width:360px;max-width:480px;max-height:80vh;overflow-y:auto;
                box-shadow:0 8px 32px rgba(0,0,0,0.25);
                font-family:'Google Sans',Roboto,Arial,sans-serif;
                color:var(--gsc-menu-fg,rgba(0,0,0,0.85));
            }
            .gsc-modal h2{margin:0 0 16px;font-size:16px;font-weight:600}
            .gsc-modal-cat{
                border:1px solid var(--gsc-menu-border,rgba(0,0,0,0.1));
                border-radius:8px;padding:10px 12px;margin-bottom:10px;
            }
            .gsc-modal-cat-header{display:flex;align-items:center;gap:8px;margin-bottom:6px}
            .gsc-modal-cat-name{font-weight:600;font-size:14px;flex:1}
            .gsc-modal-del{
                background:none;border:none;color:#d93025;cursor:pointer;font-size:18px;
                padding:0 4px;line-height:1;
            }
            .gsc-modal-del:hover{color:#a50e0e}
            .gsc-modal-keywords{
                font-size:12px;color:var(--gsc-menu-dim,rgba(0,0,0,0.5));
                margin-bottom:6px;word-break:break-all;
            }
            .gsc-modal-kw-input{
                width:100%;padding:4px 8px;border:1px solid var(--gsc-menu-border,rgba(0,0,0,0.15));
                border-radius:6px;font-size:12px;box-sizing:border-box;
                background:transparent;color:var(--gsc-menu-fg,rgba(0,0,0,0.8));
            }
            .gsc-modal-add-row{display:flex;gap:8px;margin-top:12px}
            .gsc-modal-add-input{
                flex:1;padding:6px 10px;border:1px solid var(--gsc-menu-border,rgba(0,0,0,0.15));
                border-radius:6px;font-size:13px;background:transparent;color:var(--gsc-menu-fg,rgba(0,0,0,0.8));
            }
            .gsc-btn{
                padding:6px 16px;border-radius:6px;border:none;cursor:pointer;font-size:13px;
                font-family:'Google Sans',Roboto,Arial,sans-serif;
            }
            .gsc-btn-primary{background:#4285f4;color:#fff}
            .gsc-btn-primary:hover{background:#3367d6}
            .gsc-btn-secondary{background:var(--gsc-chip-bg,rgba(0,0,0,0.06));color:var(--gsc-menu-fg,rgba(0,0,0,0.7))}
            .gsc-btn-secondary:hover{background:var(--gsc-chip-hover-bg,rgba(0,0,0,0.12))}
            .gsc-modal-footer{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
            /* ── Auto-sort confirmation modal ── */
            .gsc-sort-table{width:100%;border-collapse:collapse;font-size:12px;margin:10px 0}
            .gsc-sort-table th{text-align:left;padding:4px 8px;border-bottom:1px solid var(--gsc-menu-border,rgba(0,0,0,0.12));font-weight:600;font-size:11px;color:var(--gsc-menu-dim,rgba(0,0,0,0.5))}
            .gsc-sort-table td{padding:4px 8px;border-bottom:1px solid var(--gsc-menu-border,rgba(0,0,0,0.05))}
            .gsc-sort-table tr:hover{background:var(--gsc-menu-hover,rgba(0,0,0,0.03))}
            .gsc-sort-table tr.gsc-sort-excluded{opacity:0.35;text-decoration:line-through}
            .gsc-sort-cat{color:#4285f4;font-weight:500}
            .gsc-sort-x{background:none;border:none;color:var(--gsc-menu-dim,rgba(0,0,0,0.3));cursor:pointer;font-size:14px;padding:2px 4px;border-radius:4px}
            .gsc-sort-x:hover{color:#d93025;background:rgba(217,48,37,0.08)}
            /* Batch delete modal */
            .gsc-del-list{max-height:50vh;overflow-y:auto;margin:10px 0}
            .gsc-del-row{display:flex;align-items:center;gap:10px;padding:6px 4px;border-bottom:1px solid var(--gsc-menu-border,rgba(0,0,0,0.05));cursor:pointer}
            .gsc-del-row:hover{background:var(--gsc-menu-hover,rgba(0,0,0,0.03))}
            .gsc-del-row.selected{background:rgba(217,48,37,0.06)}
            .gsc-del-cb{width:16px;height:16px;accent-color:#d93025;cursor:pointer;flex-shrink:0}
            .gsc-del-title{font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}
            .gsc-del-cat{font-size:11px;color:#4285f4;white-space:nowrap}
            .gsc-del-selall{display:flex;align-items:center;gap:8px;padding:6px 4px;margin-bottom:4px;border-bottom:2px solid var(--gsc-menu-border,rgba(0,0,0,0.1));cursor:pointer;font-size:13px;font-weight:600}
            .gsc-del-progress{font-size:12px;color:var(--gsc-menu-dim,rgba(0,0,0,0.5));margin:8px 0}
            .gsc-btn-danger{background:#d93025;color:#fff}
            .gsc-btn-danger:hover{background:#a50e0e}
            .gsc-btn-danger:disabled{background:#ccc;cursor:not-allowed}
        `;
        document.head.appendChild(style);

        // ── Theme ──
        function applyThemeVars() {
            const isDark = document.documentElement.getAttribute('dark')!==null
                || document.body.classList.contains('dark-theme')
                || window.matchMedia('(prefers-color-scheme:dark)').matches;
            if (!isDark) return;
            const r = document.documentElement;
            r.style.setProperty('--gsc-chip-bg','rgba(255,255,255,0.08)');
            r.style.setProperty('--gsc-chip-fg','rgba(255,255,255,0.65)');
            r.style.setProperty('--gsc-chip-border','rgba(255,255,255,0.1)');
            r.style.setProperty('--gsc-chip-hover-bg','rgba(255,255,255,0.15)');
            r.style.setProperty('--gsc-chip-hover-fg','#fff');
            r.style.setProperty('--gsc-menu-bg','#2d2d2d');
            r.style.setProperty('--gsc-menu-border','rgba(255,255,255,0.15)');
            r.style.setProperty('--gsc-menu-fg','rgba(255,255,255,0.85)');
            r.style.setProperty('--gsc-menu-hover','rgba(255,255,255,0.1)');
            r.style.setProperty('--gsc-menu-dim','rgba(255,255,255,0.4)');
        }

        // ── DOM helpers ──
        function getConversationsList(){ return document.querySelector('conversations-list[data-test-id="all-conversations"]'); }
        function getTitleContainer(){ const l=getConversationsList(); return l?l.querySelector('.title-container'):null; }
        function getConversationsContainer(){ const l=getConversationsList(); return l?l.querySelector('div.conversations-container'):null; }
        function getConvItems(){ const c=getConversationsContainer(); return c?Array.from(c.querySelectorAll('div.conversation-items-container')):[]; }
        function getConvTitle(item){
            const el=item.querySelector('.conversation-title');
            if(!el) return '';
            let t=''; el.childNodes.forEach(n=>{ if(n.nodeType===Node.TEXT_NODE) t+=n.textContent; });
            return t.trim();
        }

        // ── Category bar ──
        function createCategoryBar(){
            const bar=document.createElement('div'); bar.id='gsc-category-bar';
            const cats=[ALL_LABEL,...Object.keys(categoryRules)];
            cats.forEach(cat=>{
                const chip=document.createElement('span');
                chip.className='gsc-chip'+(cat===currentFilter?' active':'');
                chip.textContent=cat;
                chip.addEventListener('click',()=>{
                    currentFilter=cat;
                    bar.querySelectorAll('.gsc-chip:not(.gsc-manage):not(.gsc-autosort)').forEach(c=>c.classList.remove('active'));
                    chip.classList.add('active');
                    applyFilter();
                });
                bar.appendChild(chip);
            });
            // ＋ manage button
            const manage=document.createElement('span');
            manage.className='gsc-chip gsc-manage'; manage.textContent='⚙'; manage.title='管理分類';
            manage.addEventListener('click',()=>showManageModal());
            bar.appendChild(manage);
            // Tools group (batch delete + auto-sort)
            const toolsGroup=document.createElement('span'); toolsGroup.className='gsc-tools-group';
            const batchDel=document.createElement('span');
            batchDel.className='gsc-chip gsc-tool'; batchDel.textContent='批量刪除';
            batchDel.title='選擇多個對話批量刪除';
            batchDel.addEventListener('click',()=>showBatchDeleteModal());
            batchDel.addEventListener('mouseenter',()=>{batchDel.style.color='#d93025';batchDel.style.borderColor='#d93025';});
            batchDel.addEventListener('mouseleave',()=>{batchDel.style.color='';batchDel.style.borderColor='';});
            toolsGroup.appendChild(batchDel);
            const autoSort=document.createElement('span');
            autoSort.className='gsc-chip gsc-tool'; autoSort.textContent='自動分類';
            autoSort.title='依關鍵字自動分類全部對話';
            autoSort.addEventListener('click',()=>showAutoSortModal());
            toolsGroup.appendChild(autoSort);
            bar.appendChild(toolsGroup);
            return bar;
        }
        function rebuildBar(){
            const old=document.getElementById('gsc-category-bar');
            if(old){ const n=createCategoryBar(); old.replaceWith(n); }
        }

        // ── Filter ──
        function applyFilter(){
            getConvItems().forEach(item=>{
                const title=getConvTitle(item); if(!title) return;
                const cat=classifyTitle(title);
                if(currentFilter===ALL_LABEL||cat===currentFilter) item.classList.remove('gsc-hidden');
                else item.classList.add('gsc-hidden');
            });
        }

        // ── Context menu (for assigning category via existing ⋮ ) ──
        function showCategoryMenu(x,y,title){
            removeContextMenu();
            const menu=document.createElement('div'); menu.className='gsc-ctx-menu';
            menu.style.left=x+'px'; menu.style.top=y+'px';
            const hdr=document.createElement('div'); hdr.className='gsc-ctx-header'; hdr.textContent='移動到分類'; menu.appendChild(hdr);
            const div=document.createElement('div'); div.className='gsc-ctx-divider'; menu.appendChild(div);
            const cur=classifyTitle(title);
            Object.keys(categoryRules).sort((a,b)=>a==='其他'?1:b==='其他'?-1:0).forEach(cat=>{
                const it=document.createElement('div'); it.className='gsc-ctx-item';
                const active=cat===cur;
                it.innerHTML=(active?'✓ ':'&nbsp;&nbsp;&nbsp;')+cat;
                if(active) it.style.fontWeight='600';
                it.addEventListener('click',e=>{
                    e.stopPropagation(); e.preventDefault();
                    manualCategories[title]=cat; saveToSwift(); applyFilter(); removeContextMenu();
                });
                menu.appendChild(it);
            });
            document.body.appendChild(menu); contextMenu=menu;
            requestAnimationFrame(()=>{
                const r=menu.getBoundingClientRect();
                if(r.right>window.innerWidth) menu.style.left=Math.max(4,window.innerWidth-r.width-8)+'px';
                if(r.bottom>window.innerHeight) menu.style.top=Math.max(4,window.innerHeight-r.height-8)+'px';
            });
        }
        function removeContextMenu(){ if(contextMenu){contextMenu.remove();contextMenu=null;} }
        document.addEventListener('click',e=>{ if(contextMenu&&!contextMenu.contains(e.target)) removeContextMenu(); });
        document.addEventListener('keydown',e=>{ if(e.key==='Escape'){ removeContextMenu(); closeAnyModal(); }});

        // ── Inject into Gemini's existing ⋮ menu ──
        // When Gemini opens its mat-menu overlay, we inject a "分類" option at the top.
        let lastClickedConvTitle = '';
        function hookExistingMenuButtons(){
            getConvItems().forEach(item=>{
                if(item.dataset.gscHooked) return;
                item.dataset.gscHooked='1';
                const btn=item.querySelector('button.conversation-actions-menu-button');
                if(!btn) return;
                btn.addEventListener('click',()=>{
                    lastClickedConvTitle=getConvTitle(item);
                    // Wait for Gemini's menu to appear in the overlay container
                    waitForGeminiMenu();
                });
                // Right-click on conversation
                const link=item.querySelector('a[data-test-id="conversation"]');
                if(link){
                    link.addEventListener('contextmenu',e=>{
                        e.preventDefault();
                        const t=getConvTitle(item);
                        if(t) showCategoryMenu(e.clientX,e.clientY,t);
                    });
                }
            });
        }

        function waitForGeminiMenu(attempts){
            attempts = attempts || 0;
            if(attempts > 15) return;
            const overlay = document.querySelector('.cdk-overlay-container');
            if(!overlay) { setTimeout(()=>waitForGeminiMenu(attempts+1),50); return; }
            const panel = overlay.querySelector('.mat-mdc-menu-panel');
            if(!panel) { setTimeout(()=>waitForGeminiMenu(attempts+1),50); return; }
            // Check if we already injected
            if(panel.querySelector('.gsc-menu-inject')) return;
            const content = panel.querySelector('.mat-mdc-menu-content');
            if(!content) return;
            // Create our "分類" item that opens a submenu
            const catItem = document.createElement('button');
            catItem.className = 'mat-mdc-menu-item mdc-list-item gsc-menu-inject';
            catItem.setAttribute('role','menuitem');
            catItem.style.cssText = 'display:flex;align-items:center;gap:8px;width:100%;padding:0 16px;height:48px;border:none;background:none;cursor:pointer;font-family:inherit;font-size:14px;color:var(--gsc-menu-fg,inherit);';
            const curCat = lastClickedConvTitle ? classifyTitle(lastClickedConvTitle) : '';
            catItem.innerHTML = '<span style="font-size:18px;width:24px;text-align:center">📂</span><span>分類' + (curCat?' · '+curCat:'') + '</span><span style="margin-left:auto;font-size:12px;opacity:0.5">▸</span>';
            catItem.addEventListener('mouseenter',function(){
                // Show submenu
                showSubCategoryMenu(catItem, lastClickedConvTitle);
            });
            catItem.addEventListener('click',function(e){
                e.stopPropagation();
                showSubCategoryMenu(catItem, lastClickedConvTitle);
            });
            // Add divider and our item at the top
            const divider = document.createElement('div');
            divider.className = 'gsc-menu-inject';
            divider.style.cssText = 'height:1px;background:var(--gsc-menu-border,rgba(0,0,0,0.08));margin:4px 0;';
            content.insertBefore(divider, content.firstChild);
            content.insertBefore(catItem, content.firstChild);
        }

        let subMenu = null;
        function showSubCategoryMenu(anchor, title){
            if(subMenu) subMenu.remove();
            const rect = anchor.getBoundingClientRect();
            const menu = document.createElement('div');
            menu.className = 'gsc-ctx-menu';
            menu.style.left = (rect.right + 2) + 'px';
            menu.style.top = rect.top + 'px';
            const cur = classifyTitle(title);
            Object.keys(categoryRules).sort((a,b)=>a==='其他'?1:b==='其他'?-1:0).forEach(cat=>{
                const it=document.createElement('div'); it.className='gsc-ctx-item';
                const active = cat===cur;
                it.innerHTML = (active?'✓ ':'&nbsp;&nbsp;&nbsp;') + cat;
                if(active) it.style.fontWeight='600';
                it.addEventListener('click',e=>{
                    e.stopPropagation(); e.preventDefault();
                    manualCategories[title]=cat; saveToSwift(); applyFilter();
                    if(subMenu){subMenu.remove();subMenu=null;}
                    // Close Gemini's menu too by pressing Escape
                    document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
                });
                menu.appendChild(it);
            });
            document.body.appendChild(menu); subMenu=menu;
            requestAnimationFrame(()=>{
                const r=menu.getBoundingClientRect();
                // If overflows right, show to the left of anchor
                if(r.right>window.innerWidth) menu.style.left=(rect.left-r.width-2)+'px';
                if(r.bottom>window.innerHeight) menu.style.top=Math.max(4,window.innerHeight-r.height-8)+'px';
            });
            // Close submenu when mouse leaves both anchor and submenu
            const closeCheck=()=>{
                setTimeout(()=>{
                    if(subMenu && !subMenu.matches(':hover') && !anchor.matches(':hover')){
                        subMenu.remove(); subMenu=null;
                    }
                },200);
            };
            anchor.addEventListener('mouseleave',closeCheck);
            menu.addEventListener('mouseleave',closeCheck);
        }

        // ══════════════════════════════════════
        // ── Manage Categories Modal ──
        // ══════════════════════════════════════
        let modalOverlay = null;
        function closeAnyModal(){ if(modalOverlay){modalOverlay.remove();modalOverlay=null;} }

        function showManageModal(){
            closeAnyModal();
            const overlay=document.createElement('div'); overlay.className='gsc-overlay'; modalOverlay=overlay;
            overlay.addEventListener('click',e=>{ if(e.target===overlay) closeAnyModal(); });
            const modal=document.createElement('div'); modal.className='gsc-modal';
            const title=document.createElement('h2'); title.textContent='管理分類'; modal.appendChild(title);

            // editable copy
            let editRules = JSON.parse(JSON.stringify(categoryRules));

            function renderCategories(){
                // remove old list
                modal.querySelectorAll('.gsc-modal-cat,.gsc-modal-add-row,.gsc-modal-footer').forEach(e=>e.remove());
                const catNames = Object.keys(editRules).sort((a,b)=>a==='其他'?1:b==='其他'?-1:0);
                catNames.forEach(cat=>{
                    const card=document.createElement('div'); card.className='gsc-modal-cat';
                    const header=document.createElement('div'); header.className='gsc-modal-cat-header';
                    const nameSpan=document.createElement('span'); nameSpan.className='gsc-modal-cat-name'; nameSpan.textContent=cat;
                    header.appendChild(nameSpan);
                    if(cat!=='其他'){
                        const del=document.createElement('button'); del.className='gsc-modal-del'; del.textContent='✕'; del.title='刪除分類';
                        del.addEventListener('click',()=>{ delete editRules[cat]; renderCategories(); });
                        header.appendChild(del);
                    }
                    card.appendChild(header);

                    const kwLabel=document.createElement('div'); kwLabel.className='gsc-modal-keywords';
                    kwLabel.textContent='關鍵字（逗號分隔）：';
                    card.appendChild(kwLabel);

                    const kwInput=document.createElement('input'); kwInput.className='gsc-modal-kw-input';
                    kwInput.value=(editRules[cat]||[]).join(', ');
                    kwInput.placeholder=cat==='其他'?'預設分類（無需關鍵字）':'輸入關鍵字...';
                    if(cat==='其他') kwInput.disabled=true;
                    kwInput.addEventListener('input',()=>{
                        editRules[cat]=kwInput.value.split(',').map(s=>s.trim()).filter(Boolean);
                    });
                    card.appendChild(kwInput);
                    modal.appendChild(card);
                });

                // Add new category row
                const addRow=document.createElement('div'); addRow.className='gsc-modal-add-row';
                const addInput=document.createElement('input'); addInput.className='gsc-modal-add-input';
                addInput.placeholder='新分類名稱...';
                const addBtn=document.createElement('button'); addBtn.className='gsc-btn gsc-btn-secondary'; addBtn.textContent='新增';
                addBtn.addEventListener('click',()=>{
                    const name=addInput.value.trim();
                    if(name && !editRules[name]){ editRules[name]=[]; renderCategories(); }
                });
                addInput.addEventListener('keydown',e=>{ if(e.key==='Enter') addBtn.click(); });
                addRow.appendChild(addInput); addRow.appendChild(addBtn);
                modal.appendChild(addRow);

                // Footer
                const footer=document.createElement('div'); footer.className='gsc-modal-footer';
                const cancelBtn=document.createElement('button'); cancelBtn.className='gsc-btn gsc-btn-secondary'; cancelBtn.textContent='取消';
                cancelBtn.addEventListener('click',()=>closeAnyModal());
                const saveBtn=document.createElement('button'); saveBtn.className='gsc-btn gsc-btn-primary'; saveBtn.textContent='儲存';
                saveBtn.addEventListener('click',()=>{
                    categoryRules=editRules;
                    if(!categoryRules["其他"]) categoryRules["其他"]=[];
                    saveRulesToSwift();
                    if(currentFilter!==ALL_LABEL && !categoryRules[currentFilter]) currentFilter=ALL_LABEL;
                    rebuildBar(); applyFilter(); closeAnyModal();
                });
                footer.appendChild(cancelBtn); footer.appendChild(saveBtn);
                modal.appendChild(footer);
            }
            renderCategories();
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        // ══════════════════════════════════════
        // ── Batch Delete Modal ──
        // ══════════════════════════════════════
        function showBatchDeleteModal(){
            closeAnyModal();
            const overlay=document.createElement('div'); overlay.className='gsc-overlay'; modalOverlay=overlay;
            overlay.addEventListener('click',e=>{ if(e.target===overlay) closeAnyModal(); });
            const modal=document.createElement('div'); modal.className='gsc-modal';
            modal.style.maxWidth='480px';
            const title=document.createElement('h2');
            title.textContent=currentFilter===ALL_LABEL?'批量刪除對話':'批量刪除對話 — '+currentFilter;
            modal.appendChild(title);

            const desc=document.createElement('div');
            desc.style.cssText='font-size:12px;color:var(--gsc-menu-dim,rgba(0,0,0,0.5));margin-bottom:10px';
            desc.textContent=currentFilter===ALL_LABEL
                ?'勾選要刪除的對話，點擊「刪除選取」執行。刪除後無法復原。'
                :'僅顯示「'+currentFilter+'」分類的對話。勾選要刪除的對話，點擊「刪除選取」執行。刪除後無法復原。';
            modal.appendChild(desc);

            const items=getConvItems();
            const convData=[];
            items.forEach(item=>{
                const t=getConvTitle(item); if(!t) return;
                const cat=classifyTitle(t);
                if(currentFilter!==ALL_LABEL && cat!==currentFilter) return;
                convData.push({title:t, category:cat, el:item});
            });

            const selected=new Set();

            // Select all row
            const selAllRow=document.createElement('div'); selAllRow.className='gsc-del-selall';
            const selAllCb=document.createElement('input'); selAllCb.type='checkbox'; selAllCb.className='gsc-del-cb';
            const selAllLabel=document.createElement('span'); selAllLabel.textContent='全選 / 取消全選';
            selAllRow.appendChild(selAllCb); selAllRow.appendChild(selAllLabel);
            selAllRow.addEventListener('click',e=>{
                if(e.target===selAllCb) return;
                selAllCb.checked=!selAllCb.checked;
                selAllCb.dispatchEvent(new Event('change'));
            });

            const list=document.createElement('div'); list.className='gsc-del-list';
            const rowEls=[];

            convData.forEach((conv,idx)=>{
                const row=document.createElement('div'); row.className='gsc-del-row';
                const cb=document.createElement('input'); cb.type='checkbox'; cb.className='gsc-del-cb'; cb.dataset.idx=idx;
                const titleSpan=document.createElement('span'); titleSpan.className='gsc-del-title'; titleSpan.textContent=conv.title; titleSpan.title=conv.title;
                const catSpan=document.createElement('span'); catSpan.className='gsc-del-cat'; catSpan.textContent=conv.category;
                row.appendChild(cb); row.appendChild(titleSpan); row.appendChild(catSpan);

                cb.addEventListener('change',()=>{
                    if(cb.checked){ selected.add(idx); row.classList.add('selected'); }
                    else{ selected.delete(idx); row.classList.remove('selected'); }
                    updateCount();
                });
                row.addEventListener('click',e=>{
                    if(e.target===cb) return;
                    cb.checked=!cb.checked;
                    cb.dispatchEvent(new Event('change'));
                });
                list.appendChild(row);
                rowEls.push({row,cb});
            });

            selAllCb.addEventListener('change',()=>{
                rowEls.forEach(({row,cb},idx)=>{
                    cb.checked=selAllCb.checked;
                    if(selAllCb.checked){ selected.add(idx); row.classList.add('selected'); }
                    else{ selected.delete(idx); row.classList.remove('selected'); }
                });
                updateCount();
            });

            modal.appendChild(selAllRow);
            modal.appendChild(list);

            const countLabel=document.createElement('div'); countLabel.className='gsc-del-progress';
            function updateCount(){ countLabel.textContent='已選取 '+selected.size+' / '+convData.length+' 個對話'; delBtn.disabled=selected.size===0; }

            modal.appendChild(countLabel);

            const footer=document.createElement('div'); footer.className='gsc-modal-footer';
            const cancelBtn=document.createElement('button'); cancelBtn.className='gsc-btn gsc-btn-secondary'; cancelBtn.textContent='取消';
            cancelBtn.addEventListener('click',()=>closeAnyModal());
            let deleting=false;
            const delBtn=document.createElement('button'); delBtn.className='gsc-btn gsc-btn-danger'; delBtn.textContent='刪除選取'; delBtn.disabled=true;
            delBtn.addEventListener('click',()=>{
                if(deleting) return;
                deleting=true;
                executeBatchDelete(convData,selected,countLabel,delBtn,cancelBtn,rowEls,list);
            });
            footer.appendChild(cancelBtn); footer.appendChild(delBtn);
            modal.appendChild(footer);
            updateCount();
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        let batchDeleteCancelled=false;

        async function executeBatchDelete(convData,selected,countLabel,delBtn,cancelBtn,rowEls,list){
            batchDeleteCancelled=false;
            const indices=Array.from(selected).sort((a,b)=>b-a); // delete from bottom up
            const total=indices.length;

            // Close the modal overlay first so we can interact with the sidebar
            closeAnyModal();

            // Create a floating status bar
            const statusBar=document.createElement('div');
            statusBar.style.cssText='position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#2d2d2d;color:#fff;padding:10px 20px;border-radius:10px;z-index:999999;font-size:13px;box-shadow:0 4px 16px rgba(0,0,0,0.3);display:flex;align-items:center;gap:10px;font-family:-apple-system,sans-serif';
            const statusText=document.createElement('span');
            const cancelBtnFloat=document.createElement('button');
            cancelBtnFloat.textContent='取消';
            cancelBtnFloat.style.cssText='background:rgba(255,255,255,0.15);border:none;color:#fff;padding:4px 12px;border-radius:6px;cursor:pointer;font-size:12px';
            cancelBtnFloat.addEventListener('click',()=>{ batchDeleteCancelled=true; });
            statusBar.appendChild(statusText);
            statusBar.appendChild(cancelBtnFloat);
            document.body.appendChild(statusBar);

            let done=0;

            for(const idx of indices){
                if(batchDeleteCancelled) break;
                const conv=convData[idx];
                statusText.innerHTML='<span class="gsc-spinner"></span>正在刪除 ('+(done+1)+'/'+total+'): '+conv.title;
                try {
                    await deleteOneConversation(conv.el);
                    done++;
                    delete manualCategories[conv.title];
                } catch(e){
                    statusText.innerHTML='<span class="gsc-spinner"></span>刪除失敗: '+conv.title+' ('+e.message+')';
                    await sleep(1500);
                }
                await sleep(800);
            }
            saveToSwift();
            if(batchDeleteCancelled){
                statusText.textContent='已取消，成功刪除 '+done+' 個對話';
            } else {
                statusText.textContent='已刪除 '+done+' 個對話';
            }
            cancelBtnFloat.textContent='關閉';
            cancelBtnFloat.onclick=()=>{ statusBar.remove(); applyFilter(); };
            setTimeout(()=>{ statusBar.remove(); applyFilter(); },3000);
        }

        function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

        function deleteOneConversation(chatEl){
            return new Promise(async (resolve,reject)=>{
                if(!chatEl){ reject(new Error('找不到對話元素')); return; }

                // Step 1: Hover the conversation item to reveal the ⋮ button
                chatEl.dispatchEvent(new MouseEvent('mouseenter',{bubbles:true}));
                chatEl.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));
                await sleep(400);

                // Step 2: Find the menu button (may only appear on hover)
                let menuBtn=null;
                for(let attempt=0; attempt<5; attempt++){
                    menuBtn=chatEl.querySelector('button.conversation-actions-menu-button')
                        || chatEl.querySelector('button[aria-label*="選項"]')
                        || chatEl.querySelector('button[aria-label*="Options"]')
                        || chatEl.querySelector('button[aria-label*="More"]')
                        || chatEl.querySelector('button[aria-haspopup="menu"]');
                    if(!menuBtn){
                        // Fallback: find small buttons that look like menu triggers
                        const btns=chatEl.querySelectorAll('button');
                        for(const b of btns){
                            const r=b.getBoundingClientRect();
                            if(r.width>0 && r.width<50 && r.height>0){ menuBtn=b; break; }
                        }
                    }
                    if(menuBtn) break;
                    // Re-hover in case it didn't register
                    chatEl.dispatchEvent(new MouseEvent('mouseenter',{bubbles:true}));
                    chatEl.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}));
                    await sleep(300);
                }
                if(!menuBtn){ reject(new Error('找不到選單按鈕')); return; }

                // Step 3: Click menu button
                menuBtn.click();
                await sleep(500);

                // Step 4: Find the delete option in the overlay menu (with retries)
                let deleteBtn=null;
                for(let attempt=0; attempt<8; attempt++){
                    const overlay=document.querySelector('.cdk-overlay-container');
                    if(overlay){
                        const allItems=overlay.querySelectorAll('[role="menuitem"], button, [mat-menu-item]');
                        for(const item of allItems){
                            const text=item.textContent.trim();
                            if(text.includes('刪除') || text.includes('Delete') || text.includes('delete')){
                                deleteBtn=item; break;
                            }
                        }
                    }
                    if(deleteBtn) break;
                    await sleep(300);
                }
                if(!deleteBtn){
                    document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));
                    reject(new Error('找不到刪除選項')); return;
                }
                deleteBtn.click();
                await sleep(500);

                // Step 5: Handle confirmation dialog
                let confirmed=false;
                for(let attempt=0; attempt<6; attempt++){
                    const dialogBtns=document.querySelectorAll('.cdk-overlay-container button, [role="dialog"] button, [class*="dialog"] button');
                    for(const btn of dialogBtns){
                        if(btn===deleteBtn) continue;
                        const text=btn.textContent.trim();
                        if(text.includes('刪除') || text.includes('Delete') || text.includes('delete')){
                            btn.click(); confirmed=true; break;
                        }
                    }
                    if(confirmed) break;
                    await sleep(300);
                }
                await sleep(300);
                resolve();
            });
        }

        // ══════════════════════════════════════
        // ── Auto-Sort Confirmation Modal ──
        // ══════════════════════════════════════
        function showAutoSortModal(){
            closeAnyModal();
            const overlay=document.createElement('div'); overlay.className='gsc-overlay'; modalOverlay=overlay;
            overlay.addEventListener('click',e=>{ if(e.target===overlay) closeAnyModal(); });
            const modal=document.createElement('div'); modal.className='gsc-modal';
            modal.style.maxWidth='540px';
            const title=document.createElement('h2'); title.textContent='自動分類預覽'; modal.appendChild(title);

            const desc=document.createElement('div');
            desc.style.cssText='font-size:12px;color:var(--gsc-menu-dim,rgba(0,0,0,0.5));margin-bottom:12px';
            desc.textContent='以下是根據關鍵字規則自動歸類的結果。不想變更的對話可按 ✕ 排除。確認後套用。';
            modal.appendChild(desc);

            const table=document.createElement('table'); table.className='gsc-sort-table';
            const thead=document.createElement('thead');
            thead.innerHTML='<tr><th>對話</th><th>目前</th><th>自動分類</th><th style="width:32px"></th></tr>';
            table.appendChild(thead);
            const tbody=document.createElement('tbody');

            const items=getConvItems();
            // Pre-exclude conversations that already have manual overrides
            const excluded=new Set(Object.keys(manualCategories));
            const rows=[];
            items.forEach(item=>{
                const t=getConvTitle(item); if(!t) return;
                const curCat=classifyTitle(t);
                const autoCat=autoClassifyTitle(t);
                rows.push({title:t, current:curCat, auto:autoCat});
            });
            // Sort: "其他" auto-category at the bottom
            rows.sort((a,b)=>{
                if(a.auto==='其他'&&b.auto!=='其他') return 1;
                if(a.auto!=='其他'&&b.auto==='其他') return -1;
                return 0;
            });
            rows.forEach(row=>{
                const tr=document.createElement('tr');
                const changed=row.current!==row.auto;
                tr.innerHTML='<td style="max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="'+row.title.replace(/"/g,'&quot;')+'">'+row.title+'</td>'
                    +'<td class="gsc-sort-cat">'+row.current+'</td>'
                    +'<td class="gsc-sort-cat" style="'+(changed?'color:#d93025;font-weight:600':'')+'">'+row.auto+(changed?' ←':'')+'</td>'
                    +'<td></td>';
                // Add X button
                const isExcluded=excluded.has(row.title);
                if(isExcluded) tr.classList.add('gsc-sort-excluded');
                const xBtn=document.createElement('button'); xBtn.className='gsc-sort-x';
                xBtn.textContent=isExcluded?'↩':'✕';
                xBtn.title=isExcluded?'恢復自動分類':'排除此對話（保留目前分類）';
                xBtn.addEventListener('click',()=>{
                    if(excluded.has(row.title)){
                        excluded.delete(row.title);
                        tr.classList.remove('gsc-sort-excluded');
                        xBtn.textContent='✕'; xBtn.title='排除此對話（保留目前分類）';
                    } else {
                        excluded.add(row.title);
                        tr.classList.add('gsc-sort-excluded');
                        xBtn.textContent='↩'; xBtn.title='恢復自動分類';
                    }
                });
                tr.lastChild.appendChild(xBtn);
                tbody.appendChild(tr);
            });
            table.appendChild(tbody); modal.appendChild(table);

            const footer=document.createElement('div'); footer.className='gsc-modal-footer';
            const cancelBtn=document.createElement('button'); cancelBtn.className='gsc-btn gsc-btn-secondary'; cancelBtn.textContent='取消';
            cancelBtn.addEventListener('click',()=>closeAnyModal());
            const confirmBtn=document.createElement('button'); confirmBtn.className='gsc-btn gsc-btn-primary'; confirmBtn.textContent='確認套用';
            confirmBtn.addEventListener('click',()=>{
                // For non-excluded items, clear manual override so auto-classify kicks in
                // For excluded items, keep their current manual category
                const newManual={};
                rows.forEach(row=>{
                    if(excluded.has(row.title)){
                        // Keep current category as manual override
                        newManual[row.title]=row.current;
                    }
                    // else: don't set manual, let auto-classify handle it
                });
                manualCategories=newManual;
                saveToSwift();
                applyFilter(); closeAnyModal();
            });
            footer.appendChild(cancelBtn); footer.appendChild(confirmBtn);
            modal.appendChild(footer);
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        // ── Inject bar ──
        function injectBar(){
            if(document.getElementById('gsc-category-bar')) return true;
            const titleContainer=getTitleContainer();
            if(!titleContainer) return false;
            const bar=createCategoryBar();
            titleContainer.parentElement.insertBefore(bar,titleContainer.nextSibling);
            hookExistingMenuButtons();
            applyFilter();
            return true;
        }

        // ── Observer ──
        let debounceTimer=null;
        const observer=new MutationObserver(()=>{
            clearTimeout(debounceTimer);
            debounceTimer=setTimeout(()=>{
                if(!document.getElementById('gsc-category-bar')) injectBar();
                else { hookExistingMenuButtons(); if(currentFilter!==ALL_LABEL) applyFilter(); }
            },600);
        });

        function init(){
            applyThemeVars(); loadFromSwift();
            if(!injectBar()){
                const ri=setInterval(()=>{ if(injectBar()) clearInterval(ri); },1000);
                setTimeout(()=>clearInterval(ri),30000);
            }
            observer.observe(document.body,{childList:true,subtree:true});
        }
        if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',init);
        else init();
    })();
    """

    static func installGeminiSidebarScript(into configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        if controller.userScripts.contains(where: { $0.source == geminiSidebarScript }) {
            return
        }
        let script = WKUserScript(
            source: geminiSidebarScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
    }

    // MARK: - ChatGPT Sidebar Category Script

    private static let chatgptSidebarScript = """
    (function() {
        if (window.__chatgptSidebarInjected) return;
        window.__chatgptSidebarInjected = true;
        if (!location.hostname.includes('chatgpt.com')) return;

        const DEFAULT_RULES = {
            "程式": ["code","API","JSON","bug","程式","開發","debug","python","javascript","模型","swift","css","html","react","node"],
            "工作": ["工作","報告","會議","專案","企劃","簡報","email"],
            "學習": ["學習","教學","筆記","研究","分析","論文"],
            "遊戲": ["遊戲","攻略","博德之門","game","steam"],
            "其他": []
        };
        let categoryRules = JSON.parse(JSON.stringify(DEFAULT_RULES));
        let manualCategories = {};
        const ALL_LABEL = "全部";
        let currentFilter = ALL_LABEL;
        let contextMenu = null;

        // ── Swift bridge ──
        function loadFromSwift() {
            try {
                window.webkit.messageHandlers.chatgptCategories.postMessage({action:"load"});
                window.webkit.messageHandlers.chatgptCategories.postMessage({action:"loadRules"});
            } catch(e){}
        }
        window.__chatgptLoadCategories = function(d) {
            if (d && typeof d === 'object') { manualCategories = d; applyFilter(); }
        };
        window.__chatgptLoadRules = function(d) {
            if (d && typeof d === 'object' && Object.keys(d).length > 0) {
                categoryRules = d;
                if (!categoryRules["其他"]) categoryRules["其他"] = [];
                rebuildBar(); applyFilter();
            }
        };
        function saveToSwift() {
            try { window.webkit.messageHandlers.chatgptCategories.postMessage({action:"save",data:manualCategories}); } catch(e){}
        }
        function saveRulesToSwift() {
            try { window.webkit.messageHandlers.chatgptCategories.postMessage({action:"saveRules",data:categoryRules}); } catch(e){}
        }

        function classifyTitle(title) {
            if (manualCategories[title]) return manualCategories[title];
            const lower = title.toLowerCase();
            for (const [cat, keywords] of Object.entries(categoryRules)) {
                if (cat === "其他") continue;
                for (const kw of keywords) {
                    if (lower.includes(kw.toLowerCase())) return cat;
                }
            }
            return "其他";
        }
        function autoClassifyTitle(title) {
            const lower = title.toLowerCase();
            for (const [cat, keywords] of Object.entries(categoryRules)) {
                if (cat === "其他") continue;
                for (const kw of keywords) {
                    if (lower.includes(kw.toLowerCase())) return cat;
                }
            }
            return "其他";
        }

        // ── CSS ──
        const style = document.createElement('style');
        style.textContent = `
            #cgpt-category-bar {
                display:flex !important; gap:6px !important; padding:8px 12px !important;
                overflow-x:auto; scrollbar-width:none; flex-wrap:wrap; align-items:center;
                opacity:1 !important; visibility:visible !important;
                position:sticky; top:0; z-index:50;
                background:var(--sidebar-bg, #f9f9f9) !important;
                border-bottom:1px solid rgba(0,0,0,0.06);
            }
            @media(prefers-color-scheme:dark){
                #cgpt-category-bar{background:var(--sidebar-bg, #171717) !important;border-bottom-color:rgba(255,255,255,0.06)}
            }
            #cgpt-category-bar::-webkit-scrollbar{display:none}
            /* When filtering is active, hide all conversation links by default */
            body.cgpt-filtering a[href*="/c/"] {
                height:0 !important; overflow:hidden !important; opacity:0 !important;
                pointer-events:none !important; margin:0 !important; padding:0 !important;
                position:absolute !important;
            }
            /* Show only items marked as visible */
            body.cgpt-filtering a[href*="/c/"].cgpt-visible {
                height:auto !important; overflow:visible !important; opacity:1 !important;
                pointer-events:auto !important; margin:initial !important; padding:initial !important;
                position:relative !important;
            }
            .cgpt-chip {
                padding:4px 12px !important; border-radius:14px !important; font-size:12px !important;
                cursor:pointer !important; white-space:nowrap;
                background:rgba(0,0,0,0.06) !important;
                color:rgba(0,0,0,0.6) !important;
                border:1px solid rgba(0,0,0,0.1) !important;
                transition:all .15s; user-select:none; line-height:1.5;
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                opacity:1 !important; visibility:visible !important;
                display:inline-block !important;
            }
            .cgpt-chip:hover{background:rgba(0,0,0,0.12) !important;color:rgba(0,0,0,0.85) !important}
            .cgpt-chip.active{background:#10a37f !important;color:#fff !important;border-color:#10a37f !important}
            @media(prefers-color-scheme:dark){
                .cgpt-chip{background:rgba(255,255,255,0.08) !important;color:rgba(255,255,255,0.65) !important;border-color:rgba(255,255,255,0.1) !important}
                .cgpt-chip:hover{background:rgba(255,255,255,0.15) !important;color:#fff !important}
                .cgpt-chip.active{background:#10a37f !important;color:#fff !important;border-color:#10a37f !important}
            }
            .cgpt-chip.cgpt-manage{
                background:transparent !important; border:1px dashed rgba(0,0,0,0.2) !important;
                color:rgba(0,0,0,0.4) !important; font-size:14px !important; padding:2px 8px !important;
            }
            .cgpt-chip.cgpt-manage:hover{color:rgba(0,0,0,0.7) !important;border-style:solid !important}
            .cgpt-tools-group{display:flex !important;gap:6px !important;margin-left:auto}
            .cgpt-chip.cgpt-tool{
                background:transparent !important; border:1px dashed rgba(0,0,0,0.2) !important;
                color:rgba(0,0,0,0.4) !important; font-size:11px !important; padding:3px 8px !important;
            }
            .cgpt-chip.cgpt-tool:hover{color:#10a37f !important;border-color:#10a37f !important}
            @media(prefers-color-scheme:dark){
                .cgpt-chip.cgpt-manage{border-color:rgba(255,255,255,0.15) !important;color:rgba(255,255,255,0.4) !important}
                .cgpt-chip.cgpt-manage:hover{color:rgba(255,255,255,0.7) !important}
                .cgpt-chip.cgpt-tool{border-color:rgba(255,255,255,0.15) !important;color:rgba(255,255,255,0.4) !important}
            }
            @keyframes cgptSpin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
            .cgpt-spinner{display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,0.15);border-top-color:#10a37f;border-radius:50%;animation:cgptSpin .6s linear infinite;vertical-align:middle;margin-right:6px}
            .cgpt-ctx-menu{
                position:fixed; background:#2d2d2d;
                border:1px solid rgba(255,255,255,0.15);
                border-radius:8px; padding:4px 0; min-width:160px; z-index:999999;
                box-shadow:0 4px 16px rgba(0,0,0,0.35);
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
            }
            .cgpt-ctx-item{
                padding:8px 16px; font-size:13px; color:rgba(255,255,255,0.85);
                cursor:pointer; display:flex; align-items:center; gap:8px;
            }
            .cgpt-ctx-item:hover{background:rgba(255,255,255,0.1)}
            .cgpt-ctx-header{
                padding:6px 16px 4px; font-size:11px; color:rgba(255,255,255,0.4);
                pointer-events:none; font-weight:500;
            }
            .cgpt-ctx-divider{height:1px;background:rgba(255,255,255,0.08);margin:4px 0}
            .cgpt-hidden{display:none!important}
            .cgpt-overlay{
                position:fixed;inset:0;background:rgba(0,0,0,0.45);z-index:999998;
                display:flex;align-items:center;justify-content:center;
            }
            .cgpt-modal{
                background:#2d2d2d;border-radius:12px;padding:20px 24px;
                min-width:360px;max-width:480px;max-height:80vh;overflow-y:auto;
                box-shadow:0 8px 32px rgba(0,0,0,0.4);
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
                color:rgba(255,255,255,0.85);
            }
            .cgpt-modal h2{margin:0 0 16px;font-size:16px;font-weight:600}
            .cgpt-modal-cat{
                border:1px solid rgba(255,255,255,0.1);
                border-radius:8px;padding:10px 12px;margin-bottom:10px;
            }
            .cgpt-modal-cat-header{display:flex;align-items:center;gap:8px;margin-bottom:6px}
            .cgpt-modal-cat-name{font-weight:600;font-size:14px;flex:1}
            .cgpt-modal-del{
                background:none;border:none;color:#ef4444;cursor:pointer;font-size:18px;
                padding:0 4px;line-height:1;
            }
            .cgpt-modal-del:hover{color:#dc2626}
            .cgpt-modal-keywords{
                font-size:12px;color:rgba(255,255,255,0.4);
                margin-bottom:6px;word-break:break-all;
            }
            .cgpt-modal-kw-input{
                width:100%;padding:4px 8px;border:1px solid rgba(255,255,255,0.15);
                border-radius:6px;font-size:12px;box-sizing:border-box;
                background:transparent;color:rgba(255,255,255,0.85);
            }
            .cgpt-modal-add-row{display:flex;gap:8px;margin-top:12px}
            .cgpt-modal-add-input{
                flex:1;padding:6px 10px;border:1px solid rgba(255,255,255,0.15);
                border-radius:6px;font-size:13px;background:transparent;color:rgba(255,255,255,0.85);
            }
            .cgpt-btn{
                padding:6px 16px;border-radius:6px;border:none;cursor:pointer;font-size:13px;
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
            }
            .cgpt-btn-primary{background:#10a37f;color:#fff}
            .cgpt-btn-primary:hover{background:#0d8a6a}
            .cgpt-btn-secondary{background:rgba(255,255,255,0.08);color:rgba(255,255,255,0.7)}
            .cgpt-btn-secondary:hover{background:rgba(255,255,255,0.15)}
            .cgpt-modal-footer{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
            .cgpt-sort-table{width:100%;border-collapse:collapse;font-size:12px;margin:10px 0}
            .cgpt-sort-table th{text-align:left;padding:4px 8px;border-bottom:1px solid rgba(255,255,255,0.12);font-weight:600;font-size:11px;color:rgba(255,255,255,0.4)}
            .cgpt-sort-table td{padding:4px 8px;border-bottom:1px solid rgba(255,255,255,0.05)}
            .cgpt-sort-table tr:hover{background:rgba(255,255,255,0.03)}
            .cgpt-sort-table tr.cgpt-sort-excluded{opacity:0.35;text-decoration:line-through}
            .cgpt-sort-cat{color:#10a37f;font-weight:500}
            .cgpt-sort-x{background:none;border:none;color:rgba(255,255,255,0.3);cursor:pointer;font-size:14px;padding:2px 4px;border-radius:4px}
            .cgpt-sort-x:hover{color:#ef4444;background:rgba(239,68,68,0.08)}
            .cgpt-del-list{max-height:50vh;overflow-y:auto;margin:10px 0}
            .cgpt-del-row{display:flex;align-items:center;gap:10px;padding:6px 4px;border-bottom:1px solid rgba(255,255,255,0.05);cursor:pointer}
            .cgpt-del-row:hover{background:rgba(255,255,255,0.03)}
            .cgpt-del-row.selected{background:rgba(239,68,68,0.08)}
            .cgpt-del-cb{width:16px;height:16px;accent-color:#ef4444;cursor:pointer;flex-shrink:0}
            .cgpt-del-title{font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}
            .cgpt-del-cat{font-size:11px;color:#10a37f;white-space:nowrap}
            .cgpt-del-selall{display:flex;align-items:center;gap:8px;padding:6px 4px;margin-bottom:4px;border-bottom:2px solid rgba(255,255,255,0.1);cursor:pointer;font-size:13px;font-weight:600}
            .cgpt-del-progress{font-size:12px;color:rgba(255,255,255,0.4);margin:8px 0}
            .cgpt-btn-danger{background:#ef4444;color:#fff}
            .cgpt-btn-danger:hover{background:#dc2626}
            .cgpt-btn-danger:disabled{background:#555;cursor:not-allowed}
        `;
        document.head.appendChild(style);

        // ── DOM helpers for ChatGPT ──
        // ChatGPT loads sidebar content via AJAX; we need flexible selectors.
        function getSidebar() {
            // The main sidebar nav element
            return document.querySelector('nav[aria-label]') || document.querySelector('nav');
        }
        function getChatSection() {
            // Strategy 1: find h2/h3 that contains chat-related text
            const nav = getSidebar();
            if (!nav) return null;
            const headers = nav.querySelectorAll('h2, h3, [class*="label"]');
            for (const h of headers) {
                const t = h.textContent.trim();
                if (t.includes('你的聊天') || t.includes('Your chats') || t.includes('Chats')
                    || t.includes('你的') || t.includes('Recent') || t.includes('Today')
                    || t.includes('Yesterday') || t.includes('今天') || t.includes('昨天')) {
                    return h;
                }
            }
            // Strategy 2: find the section that contains chat links
            const chatLinks = nav.querySelectorAll('a[href*="/c/"]');
            if (chatLinks.length > 0) {
                // Return the parent section or the first chat link's container
                const firstLink = chatLinks[0];
                const section = firstLink.closest('div[class*="group"]') || firstLink.closest('ol') || firstLink.parentElement;
                return section;
            }
            return null;
        }
        function getChatItems() {
            // The sidebar chat items have specific attributes
            // From debug: sidebar links have class "__menu-item" or "sidebar" related classes
            // And they're inside the sidebar area (left < 260px), not in page-header

            // Strategy 1: find links that are sidebar menu items with /c/ href
            const sidebar = document.querySelector('[id*="sidebar"]') || document.querySelector('aside');
            let items = [];

            // Search broadly for conversation links
            const allLinks = document.querySelectorAll('a[href*="/c/"]');
            allLinks.forEach(a => {
                const rect = a.getBoundingClientRect();
                // Must be visible, in the sidebar area (left < 260), and NOT in the page header
                if (rect.width > 0 && rect.left < 260 && !a.closest('#page-header') && !a.closest('header')) {
                    items.push(a);
                }
            });

            if (items.length === 0) {
                // Strategy 2: find sidebar items by class pattern
                const sidebarLinks = document.querySelectorAll('a[data-discover="true"]');
                sidebarLinks.forEach(a => {
                    const href = a.getAttribute('href') || '';
                    const rect = a.getBoundingClientRect();
                    if (href.match(/\\/c\\//) && rect.width > 0 && rect.left < 260) {
                        items.push(a);
                    }
                });
            }

            if (items.length === 0) {
                // Strategy 3: find all <a> in the sidebar container, filter by chat-like patterns
                const sidebarEl = document.querySelector('[class*="sidebar"]');
                if (sidebarEl) {
                    const links = sidebarEl.querySelectorAll('a');
                    links.forEach(a => {
                        const href = a.getAttribute('href') || '';
                        if (href.match(/\\/c\\/[0-9a-f-]+/)) items.push(a);
                    });
                }
            }

            debugLog('getChatItems: found ' + items.length + ' items (filtered)');
            return items;
        }
        function getChatTitle(item) {
            // Try multiple approaches to get the chat title text
            const selectors = [
                '.truncate span[dir="auto"]',
                '.truncate',
                'span[dir="auto"]',
                '[class*="text-token"]',
                'p',
                'span'
            ];
            for (const sel of selectors) {
                const el = item.querySelector(sel);
                if (el) {
                    const t = el.textContent.trim();
                    if (t && t.length > 0 && t.length < 200) return t;
                }
            }
            // Fallback: get the item's own text
            const text = item.textContent.trim();
            if (text.length < 200) return text;
            return '';
        }

        // ── Category bar ──
        function createCategoryBar() {
            const bar = document.createElement('div'); bar.id = 'cgpt-category-bar';
            const cats = [ALL_LABEL, ...Object.keys(categoryRules)];
            cats.forEach(cat => {
                const chip = document.createElement('span');
                chip.className = 'cgpt-chip' + (cat === currentFilter ? ' active' : '');
                chip.textContent = cat;
                chip.addEventListener('click', () => {
                    currentFilter = cat;
                    bar.querySelectorAll('.cgpt-chip:not(.cgpt-manage):not(.cgpt-tool)').forEach(c => c.classList.remove('active'));
                    chip.classList.add('active');
                    applyFilter();
                });
                bar.appendChild(chip);
            });
            const manage = document.createElement('span');
            manage.className = 'cgpt-chip cgpt-manage'; manage.textContent = '⚙'; manage.title = '管理分類';
            manage.addEventListener('click', () => showManageModal());
            bar.appendChild(manage);
            const toolsGroup = document.createElement('span'); toolsGroup.className = 'cgpt-tools-group';
            const batchDel = document.createElement('span');
            batchDel.className = 'cgpt-chip cgpt-tool'; batchDel.textContent = '批量刪除';
            batchDel.title = '選擇多個對話批量刪除';
            batchDel.addEventListener('click', () => showBatchDeleteModal());
            batchDel.addEventListener('mouseenter', () => { batchDel.style.color = '#ef4444'; batchDel.style.borderColor = '#ef4444'; });
            batchDel.addEventListener('mouseleave', () => { batchDel.style.color = ''; batchDel.style.borderColor = ''; });
            toolsGroup.appendChild(batchDel);
            const autoSort = document.createElement('span');
            autoSort.className = 'cgpt-chip cgpt-tool'; autoSort.textContent = '自動分類';
            autoSort.title = '依關鍵字自動分類全部對話';
            autoSort.addEventListener('click', () => showAutoSortModal());
            toolsGroup.appendChild(autoSort);
            const loadAll = document.createElement('span');
            loadAll.className = 'cgpt-chip cgpt-tool'; loadAll.textContent = '載入全部';
            loadAll.title = '捲動載入所有對話歷史';
            loadAll.addEventListener('click', () => loadAllConversations(loadAll));
            toolsGroup.appendChild(loadAll);

            bar.appendChild(toolsGroup);
            return bar;
        }
        function rebuildBar() {
            const old = document.getElementById('cgpt-category-bar');
            if (old) { const n = createCategoryBar(); old.replaceWith(n); }
        }

        // ── Load all conversations by auto-scrolling ──
        async function loadAllConversations(btn) {
            if (btn) {
                btn.textContent = '載入中...';
                btn.style.color = '#10a37f';
                btn.style.borderColor = '#10a37f';
            }
            await doLoadAll(btn);
            if (btn) {
                setTimeout(() => {
                    btn.textContent = '載入全部';
                    btn.style.color = '';
                    btn.style.borderColor = '';
                }, 2000);
            }
        }

        async function doLoadAll(btn) {
            debugLog('loadAll: starting');

            const scrollContainer = findScrollContainer();
            if (!scrollContainer) {
                debugLog('loadAll: no scroll container found');
                if (btn) { btn.textContent = '載入全部'; btn.style.color = ''; btn.style.borderColor = ''; }
                return;
            }

            let prevCount = 0;
            let sameCountRounds = 0;
            const maxRounds = 80;

            for (let round = 0; round < maxRounds; round++) {
                const items = getChatItems();
                const currentCount = items.length;
                debugLog('loadAll round ' + round + ': ' + currentCount + ' items');

                if (btn) btn.textContent = '載入中... (' + currentCount + ')';

                if (currentCount === prevCount) {
                    sameCountRounds++;
                    if (sameCountRounds >= 3) {
                        debugLog('loadAll: no new items after 3 rounds, done');
                        break;
                    }
                } else {
                    sameCountRounds = 0;
                }
                prevCount = currentCount;

                // Scroll to bottom to trigger loading
                scrollContainer.scrollTop = scrollContainer.scrollHeight;
                await sleep(800);
            }

            const finalCount = getChatItems().length;
            debugLog('loadAll: finished, total ' + finalCount + ' items');

            // Scroll back to top
            if (btn) scrollContainer.scrollTop = 0;

            if (btn) {
                btn.textContent = '已載入 ' + finalCount;
                btn.style.color = '#10a37f';
            }

            // Now that all conversations are loaded, apply hooks and filter
            hookChatItems();
            applyFilter();
        }

        function findScrollContainer() {
            // Strategy 1: find the scrollable parent of chat items
            const items = getChatItems();
            if (items.length > 0) {
                let el = items[0].parentElement;
                while (el && el !== document.body) {
                    const style = window.getComputedStyle(el);
                    if ((style.overflowY === 'auto' || style.overflowY === 'scroll') && el.scrollHeight > el.clientHeight) {
                        return el;
                    }
                    el = el.parentElement;
                }
            }
            // Strategy 2: find by known ChatGPT sidebar structure
            const sidebar = document.querySelector('[class*="sidebar-expando"]');
            if (sidebar) {
                let el = sidebar.parentElement;
                while (el && el !== document.body) {
                    if (el.scrollHeight > el.clientHeight + 50) return el;
                    el = el.parentElement;
                }
            }
            // Strategy 3: find any scrollable element in the left portion
            const candidates = document.querySelectorAll('div, nav, aside');
            for (const c of candidates) {
                const rect = c.getBoundingClientRect();
                if (rect.left < 300 && rect.height > 200) {
                    const style = window.getComputedStyle(c);
                    if ((style.overflowY === 'auto' || style.overflowY === 'scroll') && c.scrollHeight > c.clientHeight + 50) {
                        return c;
                    }
                }
            }
            return null;
        }

        // ── Filter ──
        function applyFilter() {
            if (currentFilter === ALL_LABEL) {
                document.body.classList.remove('cgpt-filtering');
                getChatItems().forEach(item => { item.classList.remove('cgpt-visible'); });
            } else {
                document.body.classList.add('cgpt-filtering');
                getChatItems().forEach(item => {
                    const title = getChatTitle(item); if (!title) return;
                    const cat = classifyTitle(title);
                    if (cat === currentFilter) {
                        item.classList.add('cgpt-visible');
                    } else {
                        item.classList.remove('cgpt-visible');
                    }
                });
            }
        }

        // ── Context menu ──
        function showCategoryMenu(x, y, title) {
            removeContextMenu();
            const menu = document.createElement('div'); menu.className = 'cgpt-ctx-menu';
            menu.style.left = x + 'px'; menu.style.top = y + 'px';
            const hdr = document.createElement('div'); hdr.className = 'cgpt-ctx-header'; hdr.textContent = '移動到分類'; menu.appendChild(hdr);
            const div = document.createElement('div'); div.className = 'cgpt-ctx-divider'; menu.appendChild(div);
            const cur = classifyTitle(title);
            Object.keys(categoryRules).sort((a, b) => a === '其他' ? 1 : b === '其他' ? -1 : 0).forEach(cat => {
                const it = document.createElement('div'); it.className = 'cgpt-ctx-item';
                const active = cat === cur;
                it.innerHTML = (active ? '✓ ' : '&nbsp;&nbsp;&nbsp;') + cat;
                if (active) it.style.fontWeight = '600';
                it.addEventListener('click', e => {
                    e.stopPropagation(); e.preventDefault();
                    manualCategories[title] = cat; saveToSwift(); applyFilter(); removeContextMenu();
                });
                menu.appendChild(it);
            });
            document.body.appendChild(menu); contextMenu = menu;
            requestAnimationFrame(() => {
                const r = menu.getBoundingClientRect();
                if (r.right > window.innerWidth) menu.style.left = Math.max(4, window.innerWidth - r.width - 8) + 'px';
                if (r.bottom > window.innerHeight) menu.style.top = Math.max(4, window.innerHeight - r.height - 8) + 'px';
            });
        }
        function removeContextMenu() { if (contextMenu) { contextMenu.remove(); contextMenu = null; } }
        document.addEventListener('click', e => { if (contextMenu && !contextMenu.contains(e.target)) removeContextMenu(); });
        document.addEventListener('keydown', e => { if (e.key === 'Escape') { removeContextMenu(); closeAnyModal(); } });

        // ── Hook right-click on chat items ──
        function hookChatItems() {
            getChatItems().forEach(item => {
                if (item.dataset.cgptHooked) return;
                item.dataset.cgptHooked = '1';
                item.addEventListener('contextmenu', e => {
                    e.preventDefault();
                    const t = getChatTitle(item);
                    if (t) showCategoryMenu(e.clientX, e.clientY, t);
                });
            });
        }

        // Debug: detect when user manually opens ⋯ menu, dump what appears
        let menuDumpDone = false;
        const menuObserver = new MutationObserver(() => {
            if (menuDumpDone) return;
            const menuItems = document.querySelectorAll('[role="menuitem"]');
            if (menuItems.length > 0) {
                menuDumpDone = true;
                debugLog('=== MANUAL MENU DETECTED ===');
                debugLog('menuitem count: ' + menuItems.length);
                menuItems.forEach((item, i) => {
                    debugLog('menuitem['+i+']: tag='+item.tagName+' text="'+item.textContent.trim().substring(0,30)+'" role='+item.getAttribute('role'));
                });
                // Also check for any menu/popover containers
                const menus = document.querySelectorAll('[role="menu"], [data-radix-menu-content], [data-state="open"]');
                menus.forEach((m, i) => {
                    debugLog('menu['+i+']: tag='+m.tagName+' role='+m.getAttribute('role')+' class='+(m.className||'').substring(0,50));
                });
                setTimeout(() => { menuDumpDone = false; }, 3000);
            }
        });
        menuObserver.observe(document.body, {childList:true, subtree:true});

        // ══════════════════════════════════════
        // ── Manage Categories Modal ──
        // ══════════════════════════════════════
        let modalOverlay = null;
        function closeAnyModal() { if (modalOverlay) { modalOverlay.remove(); modalOverlay = null; } }

        function showManageModal() {
            closeAnyModal();
            const overlay = document.createElement('div'); overlay.className = 'cgpt-overlay'; modalOverlay = overlay;
            overlay.addEventListener('click', e => { if (e.target === overlay) closeAnyModal(); });
            const modal = document.createElement('div'); modal.className = 'cgpt-modal';
            const title = document.createElement('h2'); title.textContent = '管理分類'; modal.appendChild(title);
            let editRules = JSON.parse(JSON.stringify(categoryRules));

            function renderCategories() {
                modal.querySelectorAll('.cgpt-modal-cat,.cgpt-modal-add-row,.cgpt-modal-footer').forEach(e => e.remove());
                const catNames = Object.keys(editRules).sort((a, b) => a === '其他' ? 1 : b === '其他' ? -1 : 0);
                catNames.forEach(cat => {
                    const card = document.createElement('div'); card.className = 'cgpt-modal-cat';
                    const header = document.createElement('div'); header.className = 'cgpt-modal-cat-header';
                    const nameSpan = document.createElement('span'); nameSpan.className = 'cgpt-modal-cat-name'; nameSpan.textContent = cat;
                    header.appendChild(nameSpan);
                    if (cat !== '其他') {
                        const del = document.createElement('button'); del.className = 'cgpt-modal-del'; del.textContent = '✕'; del.title = '刪除分類';
                        del.addEventListener('click', () => { delete editRules[cat]; renderCategories(); });
                        header.appendChild(del);
                    }
                    card.appendChild(header);
                    const kwLabel = document.createElement('div'); kwLabel.className = 'cgpt-modal-keywords';
                    kwLabel.textContent = '關鍵字（逗號分隔）：';
                    card.appendChild(kwLabel);
                    const kwInput = document.createElement('input'); kwInput.className = 'cgpt-modal-kw-input';
                    kwInput.value = (editRules[cat] || []).join(', ');
                    kwInput.placeholder = cat === '其他' ? '預設分類（無需關鍵字）' : '輸入關鍵字...';
                    if (cat === '其他') kwInput.disabled = true;
                    kwInput.addEventListener('input', () => {
                        editRules[cat] = kwInput.value.split(',').map(s => s.trim()).filter(Boolean);
                    });
                    card.appendChild(kwInput);
                    modal.appendChild(card);
                });
                const addRow = document.createElement('div'); addRow.className = 'cgpt-modal-add-row';
                const addInput = document.createElement('input'); addInput.className = 'cgpt-modal-add-input';
                addInput.placeholder = '新分類名稱...';
                const addBtn = document.createElement('button'); addBtn.className = 'cgpt-btn cgpt-btn-secondary'; addBtn.textContent = '新增';
                addBtn.addEventListener('click', () => {
                    const name = addInput.value.trim();
                    if (name && !editRules[name]) { editRules[name] = []; renderCategories(); }
                });
                addInput.addEventListener('keydown', e => { if (e.key === 'Enter') addBtn.click(); });
                addRow.appendChild(addInput); addRow.appendChild(addBtn);
                modal.appendChild(addRow);
                const footer = document.createElement('div'); footer.className = 'cgpt-modal-footer';
                const cancelBtn = document.createElement('button'); cancelBtn.className = 'cgpt-btn cgpt-btn-secondary'; cancelBtn.textContent = '取消';
                cancelBtn.addEventListener('click', () => closeAnyModal());
                const saveBtn = document.createElement('button'); saveBtn.className = 'cgpt-btn cgpt-btn-primary'; saveBtn.textContent = '儲存';
                saveBtn.addEventListener('click', () => {
                    categoryRules = editRules;
                    if (!categoryRules["其他"]) categoryRules["其他"] = [];
                    saveRulesToSwift();
                    if (currentFilter !== ALL_LABEL && !categoryRules[currentFilter]) currentFilter = ALL_LABEL;
                    rebuildBar(); applyFilter(); closeAnyModal();
                });
                footer.appendChild(cancelBtn); footer.appendChild(saveBtn);
                modal.appendChild(footer);
            }
            renderCategories();
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        // ══════════════════════════════════════
        // ── Batch Delete Modal ──
        // ══════════════════════════════════════
        function showBatchDeleteModal() {
            closeAnyModal();
            const overlay = document.createElement('div'); overlay.className = 'cgpt-overlay'; modalOverlay = overlay;
            overlay.addEventListener('click', e => { if (e.target === overlay) closeAnyModal(); });
            const modal = document.createElement('div'); modal.className = 'cgpt-modal';
            modal.style.maxWidth = '480px';
            const title = document.createElement('h2');
            title.textContent = currentFilter === ALL_LABEL ? '批量刪除對話' : '批量刪除對話 — ' + currentFilter;
            modal.appendChild(title);
            const desc = document.createElement('div');
            desc.style.cssText = 'font-size:12px;color:rgba(255,255,255,0.4);margin-bottom:10px';
            desc.textContent = currentFilter === ALL_LABEL
                ? '勾選要刪除的對話，點擊「刪除選取」執行。刪除後無法復原。'
                : '僅顯示「' + currentFilter + '」分類的對話。勾選要刪除的對話，點擊「刪除選取」執行。刪除後無法復原。';
            modal.appendChild(desc);

            const items = getChatItems();
            const convData = [];
            items.forEach(item => {
                const t = getChatTitle(item); if (!t) return;
                const cat = classifyTitle(t);
                if (currentFilter !== ALL_LABEL && cat !== currentFilter) return;
                const href = item.getAttribute('href') || '';
                const match = href.match(/\\/c\\/([0-9a-f-]+)/);
                const convId = match ? match[1] : null;
                convData.push({ title: t, category: cat, el: item, convId: convId });
            });

            const selected = new Set();
            let lastClickedIdx = -1; // for Shift+Click range selection

            const selAllRow = document.createElement('div'); selAllRow.className = 'cgpt-del-selall';
            const selAllCb = document.createElement('input'); selAllCb.type = 'checkbox'; selAllCb.className = 'cgpt-del-cb';
            const selAllLabel = document.createElement('span'); selAllLabel.textContent = '全選 / 取消全選';
            selAllRow.appendChild(selAllCb); selAllRow.appendChild(selAllLabel);
            selAllRow.addEventListener('click', e => {
                if (e.target === selAllCb) return;
                selAllCb.checked = !selAllCb.checked;
                selAllCb.dispatchEvent(new Event('change'));
            });

            const list = document.createElement('div'); list.className = 'cgpt-del-list';
            const rowEls = [];

            function setChecked(idx, checked) {
                const { row, cb } = rowEls[idx];
                cb.checked = checked;
                if (checked) { selected.add(idx); row.classList.add('selected'); }
                else { selected.delete(idx); row.classList.remove('selected'); }
            }

            convData.forEach((conv, idx) => {
                const row = document.createElement('div'); row.className = 'cgpt-del-row';
                const cb = document.createElement('input'); cb.type = 'checkbox'; cb.className = 'cgpt-del-cb'; cb.dataset.idx = idx;
                const titleSpan = document.createElement('span'); titleSpan.className = 'cgpt-del-title'; titleSpan.textContent = conv.title; titleSpan.title = conv.title;
                const catSpan = document.createElement('span'); catSpan.className = 'cgpt-del-cat'; catSpan.textContent = conv.category;
                row.appendChild(cb); row.appendChild(titleSpan); row.appendChild(catSpan);
                cb.addEventListener('change', () => {
                    if (cb.checked) { selected.add(idx); row.classList.add('selected'); }
                    else { selected.delete(idx); row.classList.remove('selected'); }
                    updateCount();
                });
                row.addEventListener('click', e => {
                    if (e.target === cb) {
                        // Shift+Click on checkbox itself
                        if (e.shiftKey && lastClickedIdx >= 0 && lastClickedIdx !== idx) {
                            const from = Math.min(lastClickedIdx, idx);
                            const to = Math.max(lastClickedIdx, idx);
                            for (let i = from; i <= to; i++) setChecked(i, true);
                            updateCount();
                        }
                        lastClickedIdx = idx;
                        return;
                    }
                    // Shift+Click on row
                    if (e.shiftKey && lastClickedIdx >= 0 && lastClickedIdx !== idx) {
                        const from = Math.min(lastClickedIdx, idx);
                        const to = Math.max(lastClickedIdx, idx);
                        for (let i = from; i <= to; i++) setChecked(i, true);
                        updateCount();
                    } else {
                        cb.checked = !cb.checked;
                        cb.dispatchEvent(new Event('change'));
                    }
                    lastClickedIdx = idx;
                });
                list.appendChild(row);
                rowEls.push({ row, cb });
            });

            selAllCb.addEventListener('change', () => {
                rowEls.forEach(({ row, cb }, idx) => {
                    cb.checked = selAllCb.checked;
                    if (selAllCb.checked) { selected.add(idx); row.classList.add('selected'); }
                    else { selected.delete(idx); row.classList.remove('selected'); }
                });
                updateCount();
            });

            modal.appendChild(selAllRow);
            modal.appendChild(list);
            const countLabel = document.createElement('div'); countLabel.className = 'cgpt-del-progress';
            function updateCount() { countLabel.textContent = '已選取 ' + selected.size + ' / ' + convData.length + ' 個對話'; delBtn.disabled = selected.size === 0; }
            modal.appendChild(countLabel);

            const footer = document.createElement('div'); footer.className = 'cgpt-modal-footer';
            const cancelBtn = document.createElement('button'); cancelBtn.className = 'cgpt-btn cgpt-btn-secondary'; cancelBtn.textContent = '取消';
            cancelBtn.addEventListener('click', () => closeAnyModal());
            let deleting = false;
            const delBtn = document.createElement('button'); delBtn.className = 'cgpt-btn cgpt-btn-danger'; delBtn.textContent = '刪除選取'; delBtn.disabled = true;
            delBtn.addEventListener('click', () => {
                if (deleting) return;
                deleting = true;
                executeBatchDelete(convData, selected, countLabel, delBtn, cancelBtn, rowEls, list);
            });
            footer.appendChild(cancelBtn); footer.appendChild(delBtn);
            modal.appendChild(footer);
            updateCount();
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        let batchDeleteCancelled = false;

        async function executeBatchDelete(convData, selected, countLabel, delBtn, cancelBtn, rowEls, list) {
            batchDeleteCancelled = false;
            const indices = Array.from(selected).sort((a, b) => b - a);
            const total = indices.length;

            // Close the modal overlay first so we can interact with the sidebar
            closeAnyModal();

            // Create a small floating status bar instead
            const statusBar = document.createElement('div');
            statusBar.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#2d2d2d;color:#fff;padding:10px 20px;border-radius:10px;z-index:999999;font-size:13px;box-shadow:0 4px 16px rgba(0,0,0,0.3);display:flex;align-items:center;gap:10px;font-family:-apple-system,sans-serif';
            const statusText = document.createElement('span');
            const cancelBtnFloat = document.createElement('button');
            cancelBtnFloat.textContent = '取消';
            cancelBtnFloat.style.cssText = 'background:rgba(255,255,255,0.15);border:none;color:#fff;padding:4px 12px;border-radius:6px;cursor:pointer;font-size:12px';
            cancelBtnFloat.addEventListener('click', () => { batchDeleteCancelled = true; });
            statusBar.appendChild(statusText);
            statusBar.appendChild(cancelBtnFloat);
            document.body.appendChild(statusBar);

            let done = 0;
            for (const idx of indices) {
                if (batchDeleteCancelled) break;
                const conv = convData[idx];
                statusText.innerHTML = '<span class="cgpt-spinner"></span>正在刪除 (' + (done + 1) + '/' + total + '): ' + conv.title;
                try {
                    await deleteOneChatGPTConversation(conv.convId, conv.el);
                    done++;
                    delete manualCategories[conv.title];
                } catch (e) {
                    statusText.textContent = '刪除失敗: ' + conv.title + ' (' + e.message + ')';
                    await sleep(1500);
                }
                await sleep(400);
            }
            saveToSwift();
            if (batchDeleteCancelled) {
                statusText.textContent = '已取消，成功刪除 ' + done + ' 個對話';
            } else {
                statusText.textContent = '已刪除 ' + done + ' 個對話';
            }
            cancelBtnFloat.textContent = '關閉';
            cancelBtnFloat.onclick = () => { statusBar.remove(); applyFilter(); };
            setTimeout(() => { statusBar.remove(); applyFilter(); }, 3000);
        }

        function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

        let cachedAccessToken = null;
        async function getAccessToken() {
            if (cachedAccessToken) return cachedAccessToken;
            const resp = await fetch('/api/auth/session');
            if (!resp.ok) throw new Error('無法取得 session');
            const data = await resp.json();
            cachedAccessToken = data.accessToken;
            return cachedAccessToken;
        }

        async function deleteOneChatGPTConversation(convId, chatEl) {
            if (!convId) throw new Error('無對話ID');

            const token = await getAccessToken();
            if (!token) throw new Error('無法取得 access token');

            // Use ChatGPT API to delete directly — no UI simulation needed
            const resp = await fetch('/backend-api/conversation/' + convId, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ' + token
                },
                body: JSON.stringify({ is_visible: false })
            });
            if (!resp.ok) {
                const txt = await resp.text().catch(() => '');
                throw new Error('API ' + resp.status + ': ' + txt.substring(0, 80));
            }

            // Remove the element from the sidebar
            if (chatEl) {
                chatEl.style.transition = 'opacity 0.3s, height 0.3s';
                chatEl.style.opacity = '0';
                chatEl.style.height = '0';
                chatEl.style.overflow = 'hidden';
                await sleep(300);
                chatEl.remove();
            }
        }

        // ══════════════════════════════════════
        // ── Auto-Sort Confirmation Modal ──
        // ══════════════════════════════════════
        function showAutoSortModal() {
            closeAnyModal();
            const overlay = document.createElement('div'); overlay.className = 'cgpt-overlay'; modalOverlay = overlay;
            overlay.addEventListener('click', e => { if (e.target === overlay) closeAnyModal(); });
            const modal = document.createElement('div'); modal.className = 'cgpt-modal';
            modal.style.maxWidth = '540px';
            const title = document.createElement('h2'); title.textContent = '自動分類預覽'; modal.appendChild(title);
            const desc = document.createElement('div');
            desc.style.cssText = 'font-size:12px;color:rgba(255,255,255,0.4);margin-bottom:12px';
            desc.textContent = '以下是根據關鍵字規則自動歸類的結果。不想變更的對話可按 ✕ 排除。確認後套用。';
            modal.appendChild(desc);

            const table = document.createElement('table'); table.className = 'cgpt-sort-table';
            const thead = document.createElement('thead');
            thead.innerHTML = '<tr><th>對話</th><th>目前</th><th>自動分類</th><th style="width:32px"></th></tr>';
            table.appendChild(thead);
            const tbody = document.createElement('tbody');
            const excluded = new Set(Object.keys(manualCategories));
            const rows = [];
            getChatItems().forEach(item => {
                const t = getChatTitle(item); if (!t) return;
                const curCat = classifyTitle(t);
                const autoCat = autoClassifyTitle(t);
                rows.push({ title: t, current: curCat, auto: autoCat });
            });
            rows.sort((a, b) => {
                if (a.auto === '其他' && b.auto !== '其他') return 1;
                if (a.auto !== '其他' && b.auto === '其他') return -1;
                return 0;
            });
            rows.forEach(row => {
                const tr = document.createElement('tr');
                const changed = row.current !== row.auto;
                tr.innerHTML = '<td style="max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="' + row.title.replace(/"/g, '&quot;') + '">' + row.title + '</td>'
                    + '<td class="cgpt-sort-cat">' + row.current + '</td>'
                    + '<td class="cgpt-sort-cat" style="' + (changed ? 'color:#ef4444;font-weight:600' : '') + '">' + row.auto + (changed ? ' ←' : '') + '</td>'
                    + '<td></td>';
                const isExcluded = excluded.has(row.title);
                if (isExcluded) tr.classList.add('cgpt-sort-excluded');
                const xBtn = document.createElement('button'); xBtn.className = 'cgpt-sort-x';
                xBtn.textContent = isExcluded ? '↩' : '✕';
                xBtn.title = isExcluded ? '恢復自動分類' : '排除此對話（保留目前分類）';
                xBtn.addEventListener('click', () => {
                    if (excluded.has(row.title)) {
                        excluded.delete(row.title);
                        tr.classList.remove('cgpt-sort-excluded');
                        xBtn.textContent = '✕'; xBtn.title = '排除此對話（保留目前分類）';
                    } else {
                        excluded.add(row.title);
                        tr.classList.add('cgpt-sort-excluded');
                        xBtn.textContent = '↩'; xBtn.title = '恢復自動分類';
                    }
                });
                tr.lastChild.appendChild(xBtn);
                tbody.appendChild(tr);
            });
            table.appendChild(tbody); modal.appendChild(table);

            const footer = document.createElement('div'); footer.className = 'cgpt-modal-footer';
            const cancelBtn = document.createElement('button'); cancelBtn.className = 'cgpt-btn cgpt-btn-secondary'; cancelBtn.textContent = '取消';
            cancelBtn.addEventListener('click', () => closeAnyModal());
            const confirmBtn = document.createElement('button'); confirmBtn.className = 'cgpt-btn cgpt-btn-primary'; confirmBtn.textContent = '確認套用';
            confirmBtn.addEventListener('click', () => {
                const newManual = {};
                rows.forEach(row => {
                    if (excluded.has(row.title)) {
                        newManual[row.title] = row.current;
                    }
                });
                manualCategories = newManual;
                saveToSwift();
                applyFilter(); closeAnyModal();
            });
            footer.appendChild(cancelBtn); footer.appendChild(confirmBtn);
            modal.appendChild(footer);
            overlay.appendChild(modal); document.body.appendChild(overlay);
        }

        // ── Inject bar ──
        function injectBar() {
            if (document.getElementById('cgpt-category-bar')) return true;
            const chatItems = getChatItems();
            debugLog('injectBar: found ' + chatItems.length + ' chat items');
            if (chatItems.length === 0) return false;

            const bar = createCategoryBar();
            const firstItem = chatItems[0];

            // Walk up from the first chat item to find the section container
            // ChatGPT structure: <a href="/c/..."> → <div> → <div class="group/sidebar-expando-section">
            // We insert at the top of the expando-section

            // At least 1 chat item needed
            if (chatItems.length < 1) return false;

            // Find the closest sidebar-expando section
            let target = firstItem.closest('[class*="sidebar-expando"]');
            if (target) {
                debugLog('inject: inserting into sidebar-expando section');
                target.insertBefore(bar, target.firstChild);
                hookChatItems();
                applyFilter();
                return true;
            }

            // Fallback: walk up from first item, find a container that holds most chat items
            let container = firstItem.parentElement;
            while (container && container !== document.body) {
                const linksInside = container.querySelectorAll('a[href*="/c/"]');
                const rect = container.getBoundingClientRect();
                if (linksInside.length >= chatItems.length * 0.5 && rect.left < 300) {
                    debugLog('inject: found container with ' + linksInside.length + ' links');
                    container.insertBefore(bar, container.firstChild);
                    hookChatItems();
                    applyFilter();
                    return true;
                }
                container = container.parentElement;
            }

            debugLog('inject: all strategies failed');
            return false;
        }

        // ── Observer ──
        let debounceTimer = null;
        const observer = new MutationObserver(() => {
            clearTimeout(debounceTimer);
            debounceTimer = setTimeout(() => {
                if (!document.getElementById('cgpt-category-bar')) injectBar();
                else { hookChatItems(); if (currentFilter !== ALL_LABEL) applyFilter(); }
            }, 300);
        });

        function debugLog(msg) {
            console.log('[CGPT-Categories] ' + msg);
            try { window.webkit.messageHandlers.chatgptCategories.postMessage({action:'debug', msg:msg}); } catch(e){}
        }

        function dumpSidebarInfo() {
            const nav = document.querySelector('nav');
            debugLog('nav found: ' + !!nav);

            // Find all sidebar-related containers
            const sidebarEls = document.querySelectorAll('[class*="sidebar"], [id*="sidebar"]');
            debugLog('sidebar elements: ' + sidebarEls.length);
            sidebarEls.forEach((el, i) => {
                if (i < 5) {
                    const rect = el.getBoundingClientRect();
                    const links = el.querySelectorAll('a');
                    const cLinks = el.querySelectorAll('a[href*="/c/"]');
                    debugLog('sidebar['+i+']: tag=' + el.tagName + ' id=' + (el.id||'') +
                        ' class=' + el.className.substring(0,60) +
                        ' rect=' + Math.round(rect.left) + ',' + Math.round(rect.top) + ' ' + Math.round(rect.width) + 'x' + Math.round(rect.height) +
                        ' links=' + links.length + ' /c/links=' + cLinks.length);
                }
            });

            // Find all <a> with /c/ href and note which are in sidebar vs header
            const allCLinks = document.querySelectorAll('a[href*="/c/"]');
            debugLog('total /c/ links on page: ' + allCLinks.length);
            allCLinks.forEach((a, i) => {
                const rect = a.getBoundingClientRect();
                debugLog('/c/link['+i+']: href=' + (a.getAttribute('href')||'').substring(0,50) +
                    ' text=' + a.textContent.trim().substring(0,30) +
                    ' left=' + Math.round(rect.left) +
                    ' inHeader=' + !!a.closest('#page-header,header') +
                    ' parent=' + (a.parentElement?a.parentElement.tagName:'?'));
            });

            // Dump "你的聊天" related elements across entire page
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let textNode;
            while (textNode = walker.nextNode()) {
                const t = textNode.textContent.trim();
                if (t === '你的聊天' || t === 'Your chats') {
                    const p = textNode.parentElement;
                    const rect = p.getBoundingClientRect();
                    debugLog('chatLabel: text="' + t + '" parent=' + p.tagName + ' class=' + (p.className||'').substring(0,60) +
                        ' left=' + Math.round(rect.left) + ' top=' + Math.round(rect.top));
                }
            }
        }

        let autoLoaded = false;
        function tryAutoLoad() {
            if (autoLoaded) return;
            if (document.getElementById('cgpt-category-bar')) {
                autoLoaded = true;
            }
        }

        function init() {
            debugLog('init, hostname: ' + location.hostname);
            dumpSidebarInfo();
            loadFromSwift();
            if (!injectBar()) {
                debugLog('initial inject failed, starting retry...');
                const ri = setInterval(() => {
                    if (injectBar()) { clearInterval(ri); tryAutoLoad(); }
                }, 1000);
                setTimeout(() => clearInterval(ri), 30000);
            } else {
                tryAutoLoad();
            }
            observer.observe(document.body, { childList: true, subtree: true });
        }
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
        else init();
    })();
    """

    static func installChatGPTSidebarScript(into configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        if controller.userScripts.contains(where: { $0.source == chatgptSidebarScript }) {
            return
        }
        let script = WKUserScript(
            source: chatgptSidebarScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
    }

    static func installBlobDownloadHook(into configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        if controller.userScripts.contains(where: { $0.source == blobDownloadScript }) {
            return
        }
        let script = WKUserScript(
            source: blobDownloadScript,
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
