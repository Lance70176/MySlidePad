//
//  PanelView.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct PanelView: View {
    @ObservedObject private var tabStore = TabStore.shared

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                TabSidebar(tabStore: tabStore)
                Divider()
                WebContent(tabStore: tabStore)
            }
        }
        .frame(minWidth: 520)
    }
}

private struct TabSidebar: View {
    @ObservedObject var tabStore: TabStore
    @State private var draggingTabID: UUID?

    var body: some View {
        VStack(spacing: 10) {
            Button {
                tabStore.addBlankTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .padding(.top, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(tabStore.tabs) { tab in
                        TabButton(
                            tab: tab,
                            isSelected: tabStore.selectedID == tab.id,
                            onBack: { tab.webView.goBack() },
                            onForward: { tab.webView.goForward() },
                            onReload: { tab.webView.reload() },
                            onFavorite: { tabStore.addFavorite(url: tab.url) }
                        ) {
                            tabStore.selectedID = tab.id
                        } onClose: {
                            tabStore.close(tab: tab)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(draggingTabID == tab.id ? 0.8 : 0.0), lineWidth: 2)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(draggingTabID == tab.id ? 0.18 : 0.0))
                        )
                        .onDrag {
                            draggingTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabDropDelegate(
                                targetTab: tab,
                                tabStore: tabStore,
                                draggingTabID: $draggingTabID
                            )
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 34)
    }
}

private struct TabButton: View {
    let tab: WebTab
    let isSelected: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onFavorite: () -> Void
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                    )

                faviconView
            }
            .frame(width: 40, height: 40)

        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Back", action: onBack)
                .disabled(!tab.webView.canGoBack)
            Button("Forward", action: onForward)
                .disabled(!tab.webView.canGoForward)
            Button("Refresh", action: onReload)
            Button("Add to Favorites", action: onFavorite)
            Button("Close Tab", action: onClose)
        }
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var faviconView: some View {
        if let url = faviconURL(for: tab.url) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                default:
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func faviconURL(for url: URL) -> URL? {
        guard let host = url.host, url.scheme != "about" else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTab: WebTab
    let tabStore: TabStore
    @Binding var draggingTabID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingTabID, draggingID != targetTab.id else { return }
        tabStore.moveTab(from: draggingID, to: targetTab.id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTabID = nil
        return true
    }

    func dropEnded(info: DropInfo) {
        draggingTabID = nil
    }
}

private struct WebContent: View {
    @ObservedObject var tabStore: TabStore

    var body: some View {
        if let tab = tabStore.tab(for: tabStore.selectedID) {
            TabContent(tabStore: tabStore, tab: tab)
        } else {
            Text("No Tab")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TabContent: View {
    @ObservedObject var tabStore: TabStore
    @ObservedObject var tab: WebTab
    @State private var addressText: String = ""
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        if tab.url.scheme == "about" {
            StartPageView(tabStore: tabStore, tab: tab)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField("URL", text: $addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isAddressFocused)
                        .onSubmit {
                            tabStore.openURL(addressText, in: tab)
                            isAddressFocused = false
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))

                Divider()

                WebViewRepresentable(webView: tab.webView)
                    .id(tab.id)
            }
            .onAppear { addressText = tab.url.absoluteString }
            .onChange(of: tab.url) { newURL in
                if !isAddressFocused {
                    addressText = newURL.absoluteString
                }
            }
        }
    }
}

private struct StartPageView: View {
    @ObservedObject var tabStore: TabStore
    @ObservedObject var tab: WebTab
    @State private var address: String = ""
    @State private var favoriteInput: String = ""
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("New Tab")
                    .font(.system(size: 22, weight: .semibold))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search or type website name", text: $address)
                        .textFieldStyle(.plain)
                        .onSubmit { tabStore.openURL(address, in: tab) }
                    Button("Go") {
                        tabStore.openURL(address, in: tab)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Top Sites")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Button("Reset") {
                    showResetConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .confirmationDialog(
                    "Reset favorites?",
                    isPresented: $showResetConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Clear Favorites", role: .destructive) {
                        tabStore.resetFavorites()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will clear your favorites and restore defaults.")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(tabStore.favorites, id: \.self) { item in
                        FavoriteTile(urlString: item) {
                            tabStore.openURL(item, in: tab)
                        } onDelete: {
                            tabStore.removeFavorite(item)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 24))
    }
}

private struct FavoriteTile: View {
    let urlString: String
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.18))
                    faviconView
                }
                .frame(height: 48)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Favorite", action: onDelete)
        }
    }

    private var title: String {
        if let host = URL(string: urlString)?.host, host.isEmpty == false {
            return host
        }
        return urlString
    }

    @ViewBuilder
    private var faviconView: some View {
        if let url = faviconURL(for: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                default:
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private func faviconURL(for raw: String) -> URL? {
        guard let host = URL(string: raw)?.host else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }
}
