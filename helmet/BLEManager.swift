import Foundation
import Combine
import CoreBluetooth
import UserNotifications
import UIKit

// MARK: - BLE Device Model
struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    
    static func == (lhs: BLEDevice, rhs: BLEDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Connection Status
enum ConnectionStatus: Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case disconnected
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready to Scan"
        case .scanning:
            return "Scanning for Devices..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

// MARK: - Guard Mode Data
struct GuardModeData {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    
    init?(from message: String) {
        // Expected format: "GPS:37.7749,-122.4194" or "LAT:37.7749,LON:-122.4194"
        let components = message.uppercased()
        
        // Try GPS:lat,lon format
        if components.contains("GPS:") {
            let gpsPart = components.components(separatedBy: "GPS:").last ?? ""
            let coords = gpsPart.components(separatedBy: ",")
            if coords.count == 2,
               let lat = Double(coords[0].trimmingCharacters(in: .whitespaces)),
               let lon = Double(coords[1].trimmingCharacters(in: .whitespaces)) {
                self.latitude = lat
                self.longitude = lon
                self.timestamp = Date()
                return
            }
        }
        
        // Try LAT:lat,LON:lon format
        if components.contains("LAT:") && components.contains("LON:") {
            let latPart = components.components(separatedBy: "LAT:").last?.components(separatedBy: ",").first ?? ""
            let lonPart = components.components(separatedBy: "LON:").last ?? ""
            if let lat = Double(latPart.trimmingCharacters(in: .whitespaces)),
               let lon = Double(lonPart.trimmingCharacters(in: .whitespaces)) {
                self.latitude = lat
                self.longitude = lon
                self.timestamp = Date()
                return
            }
        }
        
        return nil
    }
}

// MARK: - BLE Manager
final class BLEManager: NSObject, ObservableObject {
    @Published var isBluetoothOn = false
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var discoveredDevices: [BLEDevice] = []
    @Published var receivedText = ""
    @Published var connectedDevice: BLEDevice?
    @Published var isScanning = false
    @Published var currentMode: HelmetMode = .off
    @Published var latestGuardModeData: GuardModeData?
    @Published var lastGuardModeUpdate: Date?
    
    var isConnected: Bool {
        connectionStatus.isConnected
    }
    
    var statusText: String {
        connectionStatus.displayText
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var rxChar: CBCharacteristic?
    private var alertsManager: AlertsManager?
    private var crashWorkflowManager: CrashWorkflowManager?
    private var wasInGuardModeOnDisconnect = false
    private var lastGuardLocation: AlertLocation?

    // UUIDs must match Arduino sketch (Nordic UART Service)
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // write
    private let txUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // notify

    override init() {
        super.init()
        // Configure for background BLE operation
        // Note: Restore identifier requires "bluetooth-central" background mode in Info.plist
        // For now, use basic options without restore identifier to avoid crash
        // Background BLE will still work, but state restoration won't
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: false
            // CBCentralManagerOptionRestoreIdentifierKey: "helmetBLEManager" // Enable once Info.plist is properly configured
        ]
        // Use main queue for UI updates, but BLE callbacks will work in background
        central = CBCentralManager(delegate: self, queue: .main, options: options)
        requestNotificationPermission()
    }
    
    func setAlertsManager(_ manager: AlertsManager) {
        self.alertsManager = manager
    }
    
    func setCrashWorkflowManager(_ manager: CrashWorkflowManager) {
        self.crashWorkflowManager = manager
    }
    
    func setCurrentMode(_ mode: HelmetMode) {
        print("🛡️ Mode changed to: \(mode.rawValue)")
        currentMode = mode
        wasInGuardModeOnDisconnect = (mode == .guardMode)
        print("🛡️ Guard mode tracking: \(wasInGuardModeOnDisconnect)")
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func startScan() {
        guard isBluetoothOn else {
            connectionStatus = .error("Bluetooth is OFF")
            return
        }
        
        guard !isScanning else { return }
        
        discoveredDevices.removeAll()
        connectionStatus = .scanning
        isScanning = true
        
        // Scan for devices with the specific service UUID
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Auto-stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScan()
        }
    }
    
    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        if connectionStatus == .scanning {
            connectionStatus = .idle
        }
    }
    
    func connect(to device: BLEDevice) {
        guard isBluetoothOn else {
            connectionStatus = .error("Bluetooth is OFF")
            return
        }
        
        stopScan()
        connectionStatus = .connecting
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let p = peripheral else { return }
        central.cancelPeripheralConnection(p)
    }
    
    func send(_ text: String) {
        guard let p = peripheral, let rx = rxChar, isConnected else {
            connectionStatus = .error("Not connected")
            return
        }
        
        guard !text.isEmpty else { return }
        
        let data = Data(text.utf8)
        // BLE max write size often 20 bytes unless negotiated
        let chunk = data.prefix(20)
        p.writeValue(chunk, for: rx, type: .withResponse)
    }
    
    func clearReceivedText() {
        receivedText = ""
    }
    
    private func handleError(_ error: Error?) {
        if let error = error {
            connectionStatus = .error(error.localizedDescription)
        } else {
            connectionStatus = .error("Unknown error occurred")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    // Note: willRestoreState requires CBCentralManagerOptionRestoreIdentifierKey and
    // "bluetooth-central" background mode properly configured in Info.plist
    // Commented out to avoid crash - background BLE will still work without state restoration
    /*
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("🔄 BLE Manager restoring state (app launched from background)")
        
        // Restore peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            print("🔄 Found \(peripherals.count) restored peripheral(s)")
            for peripheral in peripherals {
                if peripheral.state == .connected {
                    print("🔄 Restoring connected peripheral: \(peripheral.name ?? "Unknown")")
                    self.peripheral = peripheral
                    peripheral.delegate = self
                    
                    // Re-discover services and characteristics
                    peripheral.discoverServices([serviceUUID])
                }
            }
        }
    }
    */
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothOn = (central.state == .poweredOn)
        
        switch central.state {
        case .poweredOn:
            break
        case .poweredOff:
            connectionStatus = .error("Bluetooth is OFF")
            isScanning = false
        case .unauthorized:
            connectionStatus = .error("Bluetooth unauthorized")
        case .unsupported:
            connectionStatus = .error("Bluetooth unsupported")
        case .resetting:
            connectionStatus = .idle
        case .unknown:
            connectionStatus = .idle
        @unknown default:
            connectionStatus = .idle
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? "Unknown Device"
        let device = BLEDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: deviceName,
            rssi: RSSI.intValue
        )
        
        // Avoid duplicates
        if !discoveredDevices.contains(device) {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = .connected
        connectedDevice = discoveredDevices.first { $0.peripheral.identifier == peripheral.identifier }
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handleError(error)
        self.peripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let wasInGuardMode = currentMode == .guardMode || wasInGuardModeOnDisconnect
        
        print("🔌 Disconnected. Current mode: \(currentMode), Was in Guard mode: \(wasInGuardMode)")
        
        connectionStatus = .disconnected
        connectedDevice = nil
        txChar = nil
        rxChar = nil
        self.peripheral = nil
        
        // If disconnected while in Guard mode, create alert
        if wasInGuardMode {
            print("🛡️ Guard mode disconnection detected - creating alert")
            handleGuardModeDisconnection()
        }
        
        wasInGuardModeOnDisconnect = false
        
        if let error = error {
            handleError(error)
        }
    }
    
    private func handleGuardModeDisconnection() {
        print("📍 Handling Guard mode disconnection...")
        
        // Always create alert when disconnecting in Guard mode
        // Use last known GPS location if available, otherwise use a placeholder
        let location: AlertLocation
        
        if let lastLocation = lastGuardLocation {
            print("📍 Using last guard location: \(lastLocation.latitude), \(lastLocation.longitude)")
            location = lastLocation
        } else if let guardData = latestGuardModeData {
            print("📍 Using latest guard mode data: \(guardData.latitude), \(guardData.longitude)")
            location = AlertLocation(latitude: guardData.latitude, longitude: guardData.longitude)
            lastGuardLocation = location
        } else {
            // No GPS data available - use placeholder location
            print("📍 No GPS data available, using placeholder")
            location = AlertLocation(
                latitude: 0.0,
                longitude: 0.0,
                address: "GPS data not available"
            )
        }
        
        createHelmetLeftBehindAlert(location: location)
    }
    
    private func createHelmetLeftBehindAlert(location: AlertLocation) {
        print("🚨 Creating Helmet Left Behind alert...")
        
        // Create appropriate message based on whether GPS data was available
        let additionalInfo: String
        if lastGuardModeUpdate != nil {
            additionalInfo = "Helmet disconnected from bike. Last location received at \(lastGuardModeUpdate!.formatted(date: .abbreviated, time: .shortened))."
        } else {
            additionalInfo = "Helmet disconnected from bike. No GPS data was received before disconnection. Please check the helmet's location manually."
        }
        
        let alert = AlertItem(
            type: .helmetLeftBehind,
            timestamp: Date(),
            location: location,
            additionalInfo: additionalInfo
        )
        
        if let manager = alertsManager {
            print("✅ Adding alert to alerts manager")
            manager.addAlert(alert)
        } else {
            print("⚠️ Alerts manager is nil - alert not saved")
        }
        
        // Send notification (always, even if alerts manager is nil)
        let notificationBody: String
        if lastGuardModeUpdate != nil {
            notificationBody = "Your helmet has been disconnected. Last location: \(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude))"
        } else {
            notificationBody = "Your helmet has been disconnected in Guard mode. No GPS data was available. Please check the helmet's location."
        }
        
        print("📱 Sending notification: \(notificationBody)")
        sendNotification(title: "Helmet Left Behind", body: notificationBody)
    }
    
    private func sendNotification(title: String, body: String) {
        print("📲 Preparing notification: \(title) - \(body)")
        
        // Ensure we're on main thread
        if Thread.isMainThread {
            sendNotificationImmediate(title: title, body: body)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.sendNotificationImmediate(title: title, body: body)
            }
        }
    }
    
    private func sendNotificationImmediate(title: String, body: String) {
        // Check notification authorization status
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            
            print("📲 Notification authorization status: \(settings.authorizationStatus.rawValue)")
            
            if settings.authorizationStatus == .authorized {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.badge = NSNumber(value: (self.alertsManager?.unreadCount ?? 0) + 1)
                
                // Use a unique identifier for each notification
                let identifier = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970)"
                
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: nil // Send immediately
                )
                
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Notification error: \(error.localizedDescription)")
                    } else {
                        print("✅ Notification sent successfully: \(title)")
                    }
                }
            } else {
                print("⚠️ Notifications not authorized. Status: \(settings.authorizationStatus.rawValue)")
                // Request permission again
                self.requestNotificationPermission()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            handleError(error)
            return
        }
        
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([txUUID, rxUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            handleError(error)
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == txUUID {
                txChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid == rxUUID {
                rxChar = characteristic
            }
        }

        if txChar != nil && rxChar != nil {
            connectionStatus = .connected
        } else {
            connectionStatus = .error("Required characteristics not found")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        let appState = UIApplication.shared.applicationState
        let isBackground = (appState == .background || appState == .inactive)
        
        print("📡 didUpdateValueFor called - UUID: \(characteristic.uuid), Error: \(error?.localizedDescription ?? "none"), AppState: \(isBackground ? "BACKGROUND" : "FOREGROUND")")
        
        // Start background task if app is in background
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        if isBackground {
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                print("⚠️ Background task expired while processing BLE message")
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            print("🔄 Started background task for BLE message processing")
        }
        
        if let error = error {
            print("❌ Error receiving BLE data: \(error.localizedDescription)")
            handleError(error)
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }
        
        guard characteristic.uuid == txUUID else {
            print("⚠️ Received update for wrong characteristic: \(characteristic.uuid) (expected: \(txUUID))")
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }
        
        guard let data = characteristic.value else {
            print("⚠️ Received BLE update but data is nil")
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }
        
        guard let text = String(data: data, encoding: .utf8) else {
            print("⚠️ Failed to convert BLE data to UTF-8 string. Data: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }

        print("📥 Received BLE data chunk: '\(text)' (Current mode: \(currentMode.rawValue), Background: \(isBackground))")

        // Append received text with timestamp
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        if receivedText.isEmpty {
            receivedText = "[\(timestamp)] \(text)"
        } else {
            receivedText += "\n[\(timestamp)] \(text)"
        }
        
        // CRITICAL: Check for CRASH and THEFT FIRST (regardless of mode, works in background)
        let upperMessage = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for CRASH message
        let crashKeywords = ["CRASH", "CRSH", "CRAS", "CRASHE"]
        let containsCrash = crashKeywords.contains { keyword in
            upperMessage.contains(keyword)
        }
        
        if containsCrash {
            print("🚨🚨🚨 CRASH DETECTED IN BACKGROUND! 🚨🚨🚨")
            print("   Message: '\(text)'")
            print("   Current mode: \(currentMode.rawValue)")
            print("   App state: \(isBackground ? "BACKGROUND" : "FOREGROUND")")
            
            // Handle crash IMMEDIATELY
            if let crashManager = crashWorkflowManager {
                print("🚨 Triggering crash workflow from background...")
                crashManager.handleCrashDetected()
                print("🚨 Crash workflow triggered")
            } else {
                print("❌ ERROR: crashWorkflowManager is nil!")
            }
            
            // End background task
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }
        
        // Check for THEFT message
        let theftKeywords = ["THEFT", "THFT", "THEF"]
        let containsTheft = theftKeywords.contains { keyword in
            upperMessage.contains(keyword)
        }
        
        if containsTheft {
            print("🚨 THEFT DETECTED IN BACKGROUND!")
            print("   Message: '\(text)'")
            print("   Current mode: \(currentMode.rawValue)")
            print("   App state: \(isBackground ? "BACKGROUND" : "FOREGROUND")")
            
            // Handle theft alert immediately
            handleTheftAlert(message: text)
            
            // End background task
            if isBackground && backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            return
        }
        
        // Handle mode-specific messages (only if not CRASH/THEFT)
        if currentMode == .guardMode {
            handleGuardModeMessage(text)
        } else if currentMode == .ride {
            handleRideModeMessage(text)
        }
        
        // End background task if we started one
        if isBackground && backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }
    
    private func handleGuardModeMessage(_ message: String) {
        let upperMessage = message.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for theft alert
        if upperMessage.contains("THEFT") {
            handleTheftAlert(message: message)
            return
        }
        
        // Parse GPS coordinates from regular Guard mode message
        if let guardData = GuardModeData(from: message) {
            latestGuardModeData = guardData
            lastGuardModeUpdate = Date()
            lastGuardLocation = AlertLocation(
                latitude: guardData.latitude,
                longitude: guardData.longitude
            )
        }
    }
    
    private func handleTheftAlert(message: String) {
        print("🚨 Theft alert received: \(message)")
        print("🚨 Current thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        // Try to extract GPS coordinates from theft message
        // Expected formats:
        // "THEFT:GPS:37.7749,-122.4194"
        // "THEFT:LAT:37.7749,LON:-122.4194"
        // "THEFT GPS:37.7749,-122.4194"
        // Or just "THEFT" (will use last known location)
        
        var location: AlertLocation?
        
        // Try to parse GPS from message
        if let guardData = GuardModeData(from: message) {
            location = AlertLocation(
                latitude: guardData.latitude,
                longitude: guardData.longitude
            )
            print("📍 GPS coordinates extracted from theft message: \(guardData.latitude), \(guardData.longitude)")
        } else if let lastLocation = lastGuardLocation {
            // Use last known location if GPS not in message
            location = lastLocation
            print("📍 Using last known location: \(lastLocation.latitude), \(lastLocation.longitude)")
        } else if let guardData = latestGuardModeData {
            // Use latest guard mode data
            location = AlertLocation(
                latitude: guardData.latitude,
                longitude: guardData.longitude
            )
            print("📍 Using latest guard mode data: \(guardData.latitude), \(guardData.longitude)")
        } else {
            // No location available - use placeholder
            location = AlertLocation(
                latitude: 0.0,
                longitude: 0.0,
                address: "GPS data not available"
            )
            print("⚠️ No GPS data available for theft alert")
        }
        
        guard let theftLocation = location else {
            print("❌ Failed to determine location for theft alert")
            return
        }
        
        // Create theft alert
        let alert = AlertItem(
            type: .possibleTheft,
            timestamp: Date(),
            location: theftLocation,
            additionalInfo: "Theft detected by helmet sensors. Location: \(String(format: "%.6f", theftLocation.latitude)), \(String(format: "%.6f", theftLocation.longitude))"
        )
        
        if let manager = alertsManager {
            print("✅ Adding theft alert to alerts manager")
            manager.addAlert(alert)
        } else {
            print("⚠️ Alerts manager is nil - alert not saved")
        }
        
        // Send notification
        let notificationBody: String
        if theftLocation.latitude != 0.0 || theftLocation.longitude != 0.0 {
            notificationBody = "Possible theft detected! Location: \(String(format: "%.4f", theftLocation.latitude)), \(String(format: "%.4f", theftLocation.longitude))"
        } else {
            notificationBody = "Possible theft detected! Check the Alerts section for details."
        }
        
        print("📱 About to send theft notification")
        print("📱 Notification title: Possible Theft Detected")
        print("📱 Notification body: \(notificationBody)")
        print("📱 Alerts manager available: \(alertsManager != nil)")
        
        // Send notification (same way as Helmet Left Behind - direct call)
        sendNotification(title: "Possible Theft Detected", body: notificationBody)
        
        print("📱 sendNotification() call completed")
    }
    
    private func handleRideModeMessage(_ message: String) {
        let upperMessage = message.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for crash signal
        if upperMessage.contains("CRASH") {
            print("🚨 Crash signal received in Ride mode")
            crashWorkflowManager?.handleCrashDetected()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            handleError(error)
        }
    }
}

