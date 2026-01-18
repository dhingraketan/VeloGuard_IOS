import Foundation
import CoreLocation
import UserNotifications
import MessageUI
import UIKit
import Combine
import AudioToolbox

class CrashWorkflowManager: NSObject, ObservableObject, CLLocationManagerDelegate, MFMessageComposeViewControllerDelegate {
    @Published var isCrashDetected: Bool = false
    @Published var showCrashAlert: Bool = false
    @Published var timeRemaining: Int = 10
    @Published var crashLocation: CLLocation?
    @Published var crashTimestamp: Date?
    
    private var locationManager = CLLocationManager()
    private var countdownTimer: Timer?
    private var vibrationTimer: Timer?
    private var alertsManager: AlertsManager?
    private var userSettings: UserSettings?
    private var rideHistoryManager: RideHistoryManager?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isAppInForeground: Bool = true
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        
        // Request notification permission
        requestNotificationPermission()
        
        // Observe app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        countdownTimer?.invalidate()
        vibrationTimer?.invalidate()
        endBackgroundTask()
    }
    
    func setAlertsManager(_ manager: AlertsManager) {
        self.alertsManager = manager
        print("✅ AlertsManager connected to CrashWorkflowManager")
    }
    
    func setUserSettings(_ settings: UserSettings) {
        self.userSettings = settings
        print("✅ UserSettings connected to CrashWorkflowManager")
    }
    
    func setRideHistoryManager(_ manager: RideHistoryManager) {
        self.rideHistoryManager = manager
        print("✅ RideHistoryManager connected to CrashWorkflowManager")
    }
    
    @objc private func appMovedToBackground() {
        isAppInForeground = false
        print("📱 App moved to background")
        if isCrashDetected {
            beginBackgroundTask()
        }
    }
    
    @objc private func appMovedToForeground() {
        isAppInForeground = true
        print("📱 App moved to foreground")
        if isCrashDetected {
            showCrashAlert = true
        }
        endBackgroundTask()
    }
    
    private func beginBackgroundTask() {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                print("Background task expired.")
                self?.endBackgroundTask()
            }
            print("Background task started.")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            print("Background task ended.")
        }
    }
    
    func handleCrashDetected() {
        print("🚨 handleCrashDetected() called!")
        print("   isCrashDetected: \(isCrashDetected)")
        print("   Thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        guard !isCrashDetected else {
            print("⚠️ Crash already detected, ignoring duplicate call")
            return
        }
        
        print("🚨 Crash detected! Initiating workflow...")
        
        // Start background task immediately
        beginBackgroundTask()
        
        // Ensure we're on main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isCrashDetected = true
            self.crashTimestamp = Date()
            self.timeRemaining = 10
            
            // Show alert FIRST if app is in foreground (so user sees it immediately)
            if self.isAppInForeground {
                print("📱 App is in foreground, showing crash alert popup immediately")
                self.showCrashAlert = true
            }
            
            // Request location
            self.locationManager.requestLocation()
            
            // Start vibration (works in background)
            self.startVibration()
            
            // Start 10-second countdown
            self.startCountdown()
            
            // Send initial notification (will show even if app is in foreground)
            self.sendCrashNotification(
                title: "🚨 Crash Detected!",
                body: "A crash has been detected. Open the app to cancel or proceed.",
                timeRemaining: self.timeRemaining
            )
        }
    }
    
    private func startVibration() {
        print("📳 Starting vibration...")
        print("📳 App in foreground: \(isAppInForeground)")
        
        // Use AudioServicesPlaySystemSound for vibration (works in both foreground and background)
        var vibrationCount = 0
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            vibrationCount += 1
            
            if vibrationCount >= 20 { // 10 seconds (20 * 0.5)
                timer.invalidate()
                self.vibrationTimer = nil
                print("📳 Vibration stopped after 10 seconds")
            } else {
                // Always use AudioServicesPlaySystemSound for vibration
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                print("📳 Vibration pulse \(vibrationCount)/20")
                
                // Also use haptic feedback for stronger vibration in foreground
                if self.isAppInForeground {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.prepare() // Prepare for better performance
                    impactFeedback.impactOccurred()
                }
            }
        }
        
        // Ensure timer runs on main run loop and in common modes
        RunLoop.main.add(vibrationTimer!, forMode: .common)
        
        // Start first vibration immediately (before timer starts)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        if isAppInForeground {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
            print("📳 First vibration sent immediately")
        }
    }
    
    private func startCountdown() {
        print("⏱️ Starting 10-second countdown...")
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                self.timeRemaining -= 1
                print("⏱️ Time remaining: \(self.timeRemaining) seconds")
                
                // Send notification update every second
                self.sendCrashNotification(
                    title: "🚨 Crash Detected!",
                    body: "Auto-proceeding in \(self.timeRemaining) seconds. Open app to cancel.",
                    timeRemaining: self.timeRemaining
                )
                
                if self.timeRemaining <= 0 {
                    timer.invalidate()
                    self.countdownTimer = nil
                    print("⏱️ Countdown finished, proceeding with crash alert")
                    self.proceedWithCrashAlert()
                }
            }
        }
        
        // Ensure timer runs on main run loop and in common modes
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }
    
    func cancelCrashAlert() {
        print("✅ Crash alert cancelled by user")
        isCrashDetected = false
        crashLocation = nil
        crashTimestamp = nil
        timeRemaining = 10
        showCrashAlert = false
        
        countdownTimer?.invalidate()
        countdownTimer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        endBackgroundTask()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["CrashAlertNotification"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["CrashAlertNotification"])
    }
    
    func proceedWithCrashAlert() {
        print("🚨 Proceeding with crash alert workflow")
        
        guard let timestamp = crashTimestamp else {
            print("❌ No crash timestamp available")
            return
        }
        
        let location = crashLocation ?? locationManager.location
        
        // Create crash alert
        createCrashAlert(location: location, timestamp: timestamp)
        
        // Dismiss the crash alert view if it's showing
        if showCrashAlert {
            DispatchQueue.main.async {
                self.showCrashAlert = false
            }
        }
        
        // Delay SMS and call to ensure UI is dismissed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.sendToEmergencyContact(location: location, timestamp: timestamp)
            
            if let settings = self.userSettings, settings.callSOSOnCrash {
                print("📞 Calling 911...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.callEmergencyServices()
                }
            }
        }
        
        // Reset state
        isCrashDetected = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        endBackgroundTask()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["CrashAlertNotification"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["CrashAlertNotification"])
        
        print("✅ Crash workflow completed")
    }
    
    private func createCrashAlert(location: CLLocation?, timestamp: Date) {
        let alertLocation: AlertLocation
        if let loc = location {
            alertLocation = AlertLocation(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
        } else {
            alertLocation = AlertLocation(
                latitude: 0.0,
                longitude: 0.0,
                address: "Location not available"
            )
        }
        
        // Determine severity based on impact (simplified - in real app, use sensor data)
        let severity: CrashSeverity = .high
        
        let alert = AlertItem(
            type: .crashDetected,
            timestamp: timestamp,
            location: alertLocation,
            additionalInfo: "Crash detected at \(timestamp.formatted(date: .abbreviated, time: .shortened)). Location: \(String(format: "%.6f", alertLocation.latitude)), \(String(format: "%.6f", alertLocation.longitude))",
            severity: severity,
            isRead: false
        )
        
        if let manager = alertsManager {
            manager.addAlert(alert)
        }
    }
    
    private func sendToEmergencyContact(location: CLLocation?, timestamp: Date) {
        guard let settings = userSettings,
              !settings.emergencyContactPhone.isEmpty else {
            print("⚠️ Emergency contact not configured")
            return
        }
        
        let phoneNumber = settings.emergencyContactPhone.filter("0123456789+".contains)
        guard !phoneNumber.isEmpty else {
            print("⚠️ Emergency contact phone number is empty or invalid")
            return
        }
        
        let locationText: String
        if let loc = location {
            locationText = "https://maps.apple.com/?ll=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
        } else {
            locationText = "Location not available"
        }
        
        let message = """
        🚨 CRASH DETECTED 🚨
        
        Time: \(timestamp.formatted(date: .complete, time: .standard))
        Location: \(locationText)
        
        Please check on \(settings.name.isEmpty ? "the user" : settings.name) immediately.
        """
        
        print("📞 Preparing to send SMS to: \(settings.emergencyContactName)")
        print("📞 Phone number: \(phoneNumber)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sendSMS(to: phoneNumber, message: message)
        }
    }
    
    private func sendSMS(to phoneNumber: String, message: String) {
        print("📱 Attempting to send SMS to: \(phoneNumber)")
        
        if MFMessageComposeViewController.canSendText() {
            let controller = MFMessageComposeViewController()
            controller.recipients = [phoneNumber]
            controller.body = message
            controller.messageComposeDelegate = self
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
               var rootViewController = keyWindow.rootViewController {
                
                while let presentedViewController = rootViewController.presentedViewController {
                    rootViewController = presentedViewController
                }
                
                print("✅ SMS is available, presenting compose view")
                rootViewController.present(controller, animated: true) {
                    print("✅ SMS compose view presented successfully")
                }
            } else {
                print("❌ Could not find a suitable view controller to present SMS from")
                openMessagesApp(to: phoneNumber, message: message)
            }
        } else {
            print("⚠️ SMS not available on this device. Falling back to URL scheme")
            openMessagesApp(to: phoneNumber, message: message)
        }
    }
    
    private func openMessagesApp(to phoneNumber: String, message: String) {
        if let url = URL(string: "sms://\(phoneNumber)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url) { success in
                if success {
                    print("✅ Opened Messages app successfully")
                } else {
                    print("❌ Failed to open Messages app")
                }
            }
        }
    }
    
    private func callEmergencyServices() {
        guard let url = URL(string: "tel://911") else { return }
        UIApplication.shared.open(url) { success in
            if success {
                print("📞 Calling 911 initiated")
            } else {
                print("❌ Failed to initiate 911 call")
            }
        }
    }
    
    private func sendCrashNotification(title: String, body: String, timeRemaining: Int) {
        print("📲 Preparing to send crash notification: \(body)")
        print("📲 App in foreground: \(isAppInForeground)")
        
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            
            print("📲 Notification authorization status: \(settings.authorizationStatus.rawValue)")
            print("📲 Alert setting: \(settings.alertSetting.rawValue)")
            print("📲 Sound setting: \(settings.soundSetting.rawValue)")
            
            if settings.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.badge = NSNumber(value: (self.alertsManager?.unreadCount ?? 0) + 1)
                
                // Use critical alert level if available (requires special entitlement)
                // Otherwise use timeSensitive
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                
                content.categoryIdentifier = "CRASH_ALERT"
                content.userInfo = [
                    "crashAlert": true,
                    "timeRemaining": timeRemaining
                ]
                
                // Use unique identifier for each update to ensure it shows
                let identifier = "CrashAlertNotification_\(timeRemaining)"
                
                // Remove previous notification to avoid duplicates
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["CrashAlertNotification"])
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["CrashAlertNotification"])
                
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: nil // Send immediately
                )
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Crash Notification error: \(error.localizedDescription)")
                    } else {
                        print("✅ Crash Notification sent/updated successfully. Time remaining: \(timeRemaining)")
                        print("✅ Notification identifier: \(identifier)")
                    }
                }
            } else {
                print("⚠️ Notifications not authorized for crash alert. Status: \(settings.authorizationStatus.rawValue)")
                // Request permission if not authorized
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("✅ Notification permission granted, retrying...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.sendCrashNotification(title: title, body: body, timeRemaining: timeRemaining)
                        }
                    } else {
                        print("❌ Notification permission denied")
                    }
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else if granted {
                print("✅ Notification permission granted")
            } else {
                print("⚠️ Notification permission denied")
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.first else { return }
        crashLocation = latestLocation
        print("📍 Location updated: \(latestLocation.coordinate.latitude), \(latestLocation.coordinate.longitude)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Location authorization granted")
        case .denied, .restricted:
            print("❌ Location authorization denied or restricted")
        case .notDetermined:
            print("❓ Location authorization not determined")
        @unknown default:
            print("❓ Unknown location authorization status")
        }
    }
    
    // MARK: - MFMessageComposeViewControllerDelegate
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true) {
            print("✅ SMS compose view dismissed. Result: \(result.rawValue)")
        }
    }
}
