//
//  BackgroundAssetDemoApp.swift
//  BackgroundAssetDemo
//
//  Created by Itsuki on 2026/09/05.
//

import SwiftUI

@main
struct BackgroundAssetDemoApp: App {
    private let assetManager = AssetManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(assetManager)
        }
    }
}
