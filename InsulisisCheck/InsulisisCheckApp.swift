//
//  InsulisisCheckApp.swift
//  InsulisisCheck
//
//  Created by joaolucas on 18/06/26.
//

import SwiftUI
import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await DoseStore.shared.syncShareAcceptance(cloudKitShareMetadata)
        }
    }
}

@main
struct InsulisisCheckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DoseStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await store.syncFromCloud()
                await InsulinActivityManager.shared.refresh(store: store)
            }
        }
    }
}
