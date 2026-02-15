//
//  MacSlideApp.swift
//  MacSlide
//
//  Created by Snake on 2026/2/1.
//

import SwiftUI

@main
struct MacSlideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
