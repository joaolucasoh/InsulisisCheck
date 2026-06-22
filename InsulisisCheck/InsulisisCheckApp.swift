//
//  InsulisisCheckApp.swift
//  InsulisisCheck
//
//  Created by joaolucas on 18/06/26.
//

import SwiftUI
import CloudKit
import UIKit
import WidgetKit

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
                .onAppear {
                    LiveActivityImagePublisher.publishStaticImages()
                    InsulinNotificationManager.shared.configure()
                }
                .onOpenURL { url in
                    guard let shareURL = CloudInviteLink.shareURL(from: url) else { return }
                    Task {
                        await store.syncShareInvitation(from: shareURL)
                        await InsulinActivityManager.shared.refresh(store: store)
                        await InsulinNotificationManager.shared.refresh(entries: store.entries)
                    }
                }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            WidgetCenter.shared.reloadAllTimelines()
            Task {
                await store.syncFromCloud()
                await InsulinActivityManager.shared.refresh(store: store)
                await InsulinNotificationManager.shared.refresh(entries: store.entries)
            }
        }
    }
}
