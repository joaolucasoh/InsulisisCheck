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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await DoseStore.shared.syncShareAcceptance(cloudKitShareMetadata)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            let didUpdate = await DoseStore.shared.handleRemoteCloudChange()
            completionHandler(didUpdate ? .newData : .noData)
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
                    Task {
                        await store.prepareRemoteUpdates()
                    }
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
                await store.prepareRemoteUpdates()
                await InsulinActivityManager.shared.refresh(store: store)
                await InsulinNotificationManager.shared.refresh(entries: store.entries)
            }
        }
    }
}
