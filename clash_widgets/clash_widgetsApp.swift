//
//  clash_widgetsApp.swift
//  clash_widgets
//
//  Created by Zachary Buschmann on 1/7/26.
//

import SwiftUI
import AppIntents
import WidgetKit
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency
import AdSupport
import Combine
import UserNotifications

// MARK: - App Delegate for Notification Handling
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        handleNotificationInteraction(userInfo)
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        handleNotificationInteraction(userInfo)
        completionHandler()
    }
    
    private func handleNotificationInteraction(_ userInfo: [AnyHashable: Any]) {
        // Extract profile ID if available
        if let profileIDString = userInfo["profileID"] as? String,
           let profileID = UUID(uuidString: profileIDString) {
            // Post notification to switch profile
            NotificationCenter.default.post(
                name: NSNotification.Name("SwitchToProfileFromNotification"),
                object: profileID
            )
        }
        
        // Handle redirect to Clash of Clans using trampoline strategy
        if let targetURLString = userInfo["targetURL"] as? String,
           let url = URL(string: targetURLString) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }
}

@main
struct ClashboardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var iapManager = IAPManager.shared
    private let adConsentManager = AdConsentManager.shared
    
    init() {
        print("🚀 App Init Started")
        // Ensure test-device registration is cleared for production
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(iapManager)
                .onAppear {
                    // Request EU consent first
                    adConsentManager.gatherConsent()
                    
                    // Slight delay to ensure UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NSLog("🚀 [ADMOB_DEBUG] Requesting tracking...")
                        ATTrackingManager.requestTrackingAuthorization { status in
                            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                            NSLog("🚀 [ADMOB_DEBUG] IDFA: \(idfa)")
                            NSLog("🚀 [ADMOB_DEBUG] STATUS: \(status.rawValue)")
                            
                            // Ensure test device identifiers are empty for production
                            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = []
                        }
                    }
                }
                .onOpenURL { url in
                    // Force a widget refresh whenever the app is opened via the widget
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Also refresh when app comes to foreground normally
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}

// MARK: - Ad Consent Manager (EU Compliance)
class AdConsentManager {
    static let shared = AdConsentManager()

    func gatherConsent() {
        let parameters = RequestParameters()
        
        // Uncomment for testing EU consent flow on simulator:
        // let debugSettings = DebugSettings()
        // debugSettings.testDeviceIdentifiers = ["YOUR_TEST_ID"]
        // debugSettings.geography = .EEA
        // parameters.debugSettings = debugSettings

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
            if let error = error {
                NSLog("🚀 [UMP_ERROR] \(error.localizedDescription)")
                return
            }

            // This only shows if consent is required (e.g., first launch in EU)
            ConsentForm.loadAndPresentIfRequired(from: nil) { loadError in
                if let loadError = loadError {
                    NSLog("🚀 [UMP_LOAD_ERROR] \(loadError.localizedDescription)")
                    return
                }

                // Once consent is collected or not needed, start AdMob
                if ConsentInformation.shared.canRequestAds {
                    NSLog("🚀 [ADMOB_DEBUG] AdMob Initialized ✅ (after consent)")
                    MobileAds.shared.start()
                }
            }
        }
    }
}



// MARK: - Shortcuts: import clipboard without opening the app
// Shortcuts app flow: "Get Clipboard" -> "Import Village Data" (Text = Clipboard).
// Runs in the background (openAppWhenRun = false) and shows a result banner.
struct ImportVillageDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Village Data"
    static let description = IntentDescription("Import the copied village export into the app without opening it.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Village Data", description: "Village export JSON (pass the Clipboard here)")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var input = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            input = (clipboardTextFromPasteboard() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !input.isEmpty else {
            return .result(dialog: "Clipboard was empty. Copy your village export first.")
        }

        let service = DataService(apiKey: nil)
        let result = service.importClipboardToMatchingProfile(input: input)

        switch result {
        case .success(_, let count, _):
            // Let the app reload from disk next time it becomes active.
            UserDefaults(suiteName: DataService.appGroup)?.set(true, forKey: "import_applied_externally")
            // Give the background persistence queue time to finish writing.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return .result(dialog: "Imported! \(count) active upgrades.")
        case .missingProfile(let tag):
            return .result(dialog: "No profile found for #\(tag). Add the profile in the app first.")
        case .invalidJSON:
            return .result(dialog: "Could not parse the clipboard data.")
        }
    }
}

struct ClashDashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportVillageDataIntent(),
            phrases: ["Import village data in \(.applicationName)"],
            shortTitle: "Import Village Data",
            systemImageName: "square.and.arrow.down"
        )
    }
}
