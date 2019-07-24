//
//  AppDelegate.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import Firebase
import SwiftWebSocket

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundSessionCompletionHandler: (() -> Void)?
    
    func setupPushNotifications(for application: UIApplication) {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        if #available(iOS 10.0, *) {
            // For iOS 10 display notification (sent via APNS)
            UNUserNotificationCenter.current().delegate = self

            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization(
                options: authOptions,
                completionHandler: {_, _ in })
        } else {
            let settings: UIUserNotificationSettings =
                UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }

        application.registerForRemoteNotifications()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupPushNotifications(for: application)
        Utils.registerUserDefaults()
        if let token = Utils.getAuthToken(), !token.isEmpty {
            let tinode = Cache.getTinode()
            var success = false
            do {
                let (hostName, useTLS, _) = SettingsHelper.getConnectionSettings()
                tinode.setAutoLoginWithToken(token: token)
                _ = try tinode.connect(to: (hostName ?? Cache.kHostName), useTLS: (useTLS ?? false))?.getResult()
                let msg = try tinode.loginToken(token: token, creds: nil)?.getResult()
                if let code = msg?.ctrl?.code, code < 300 {
                    print("login successful for: \(tinode.myUid!)")
                    UiUtils.routeToChatListVC()
                    success = true
                }
            } catch SwiftWebSocket.WebSocketError.network(_)  {
                // No network connection.
                UiUtils.routeToChatListVC()
                success = true
            } catch {
                print("Failed to automatically login to Tinode: \(error).")
            }
            if !success {
                _ = tinode.logout()
            }
        }
        Cache.synchronizeContactsPeriodically()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
        // Instantiate large file helper.
        let _ = Cache.getLargeFileHelper(withIdentifier: identifier)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
@available(iOS 10.0, *)
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print(response)
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceive remoteMessage: MessagingRemoteMessage) {
        print("Received data message: \(remoteMessage.appData)")
    }
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        // Update token. Send to the app server.
    }
}

