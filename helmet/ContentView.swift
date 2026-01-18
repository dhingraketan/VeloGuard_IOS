import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var alertsManager: AlertsManager
    @ObservedObject var userSettings: UserSettings
    @ObservedObject var rideHistoryManager: RideHistoryManager
    @StateObject private var bleManager = BLEManager()
    @StateObject private var statsManager = StatsManager()
    @StateObject private var crashWorkflowManager = CrashWorkflowManager()
    @State private var selectedMode: HelmetMode = .off

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    ConnectionStatusCard(
                        status: bleManager.connectionStatus,
                        deviceName: bleManager.connectedDevice?.name
                    )
                    
                    // Today's Stats Section
                    TodaysStatsSection(statsManager: statsManager)
                    
                    // Control Buttons Section
                    ControlButtonsSection(bleManager: bleManager)
                    
                    // Device List Section
                    if !bleManager.discoveredDevices.isEmpty {
                        DeviceListSection(
                            devices: bleManager.discoveredDevices,
                            bleManager: bleManager
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Guard Mode Status (when in Guard mode)
                    if bleManager.isConnected && selectedMode == .guardMode {
                        GuardModeStatusCard(bleManager: bleManager)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Helmet Mode Section
                    if bleManager.isConnected {
                        HelmetModeSection(
                            selectedMode: $selectedMode,
                            bleManager: bleManager
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                // Connect managers
                bleManager.setAlertsManager(alertsManager)
                bleManager.setCrashWorkflowManager(crashWorkflowManager)
                crashWorkflowManager.setAlertsManager(alertsManager)
                crashWorkflowManager.setUserSettings(userSettings)
                crashWorkflowManager.setRideHistoryManager(rideHistoryManager)
                // Set initial mode
                bleManager.setCurrentMode(selectedMode)
            }
            .onChange(of: crashWorkflowManager.isCrashDetected) { oldValue, newValue in
                // Show alert when crash is detected and app comes to foreground
                if newValue && !crashWorkflowManager.showCrashAlert {
                    crashWorkflowManager.showCrashAlert = true
                }
            }
            .sheet(isPresented: $crashWorkflowManager.showCrashAlert) {
                CrashAlertView(crashWorkflowManager: crashWorkflowManager)
            }
            .onChange(of: selectedMode) { oldMode, newMode in
                // Track mode changes for disconnection detection
                bleManager.setCurrentMode(newMode)
            }
        }
    }
}

// MARK: - Stats Manager
class StatsManager: ObservableObject {
    @Published var distanceKilometers: Double = 0.0
    @Published var caloriesBurnt: Int = 0
    @Published var averageSpeed: Double = 0.0
    @Published var rideTime: TimeInterval = 0
    @Published var topSpeed: Double = 0.0
    
    private var timer: Timer?
    
    init() {
        // Load saved stats for today
        loadTodaysStats()
        
        // Start timer to update stats (simulating real-time updates)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func loadTodaysStats() {
        // In a real app, load from UserDefaults or CoreData
        // For demo, using sample data
        distanceKilometers = 12.5
        caloriesBurnt = 342
        averageSpeed = 18.5
        rideTime = 3600 // 1 hour in seconds
        topSpeed = 32.4
    }
    
    private func updateStats() {
        // Simulate gradual updates (in real app, this would come from sensors)
        // This is just for demo purposes
    }
    
    func resetTodaysStats() {
        distanceKilometers = 0.0
        caloriesBurnt = 0
        averageSpeed = 0.0
        rideTime = 0
        topSpeed = 0.0
    }
}

// MARK: - Helmet Mode Enum
enum HelmetMode: String, CaseIterable {
    case ride = "RIDE"
    case guardMode = "GUARD"
    case off = "OFF"
    
    var displayName: String {
        switch self {
        case .ride:
            return "Ride"
        case .guardMode:
            return "Guard"
        case .off:
            return "Off"
        }
    }
    
    var icon: String {
        switch self {
        case .ride:
            return "bicycle"
        case .guardMode:
            return "shield.fill"
        case .off:
            return "power"
        }
    }
    
    var color: Color {
        switch self {
        case .ride:
            return Color(red: 0.0, green: 0.48, blue: 1.0) // Blue
        case .guardMode:
            return Color(red: 1.0, green: 0.58, blue: 0.0) // Orange
        case .off:
            return .secondary
        }
    }
}

// MARK: - Connection Status Card
struct ConnectionStatusCard: View {
    let status: ConnectionStatus
    let deviceName: String?
    
    var statusColor: Color {
        switch status {
        case .connected:
            return Color(red: 0.0, green: 0.78, blue: 0.33) // Apple green
        case .scanning, .connecting:
            return .orange
        case .error:
            return Color(red: 1.0, green: 0.23, blue: 0.19) // Apple red
        default:
            return .secondary
        }
    }
    
    var statusIcon: String {
        switch status {
        case .connected:
            return "checkmark.circle.fill"
        case .scanning:
            return "antenna.radiowaves.left.and.right"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Status Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: statusIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.displayText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if let deviceName = deviceName, status.isConnected {
                        Text(deviceName)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Ready to connect")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Status indicator bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.quaternaryLabel))
                    
                    if status.isConnected {
                        Capsule()
                            .fill(statusColor)
                            .frame(width: geometry.size.width)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            .frame(height: 3)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: status.isConnected)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Control Buttons Section
struct ControlButtonsSection: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Primary Action Button
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    bleManager.startScan()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Scan for Devices")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundColor(.white)
                .background(
                    Group {
                        if bleManager.isBluetoothOn && !bleManager.isScanning {
                            Color.accentColor
                        } else {
                            Color.secondary.opacity(0.3)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!bleManager.isBluetoothOn || bleManager.isScanning)
            
            // Secondary Actions
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        bleManager.stopScan()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                        Text("Stop")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundColor(.orange)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!bleManager.isScanning)
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        bleManager.disconnect()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                        Text("Disconnect")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundColor(bleManager.isConnected ? .red : .secondary)
                    .background(
                        bleManager.isConnected ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!bleManager.isConnected)
            }
        }
    }
}

// MARK: - Device List Section
struct DeviceListSection: View {
    let devices: [BLEDevice]
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Text("Discovered Devices")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(devices.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Device List
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    DeviceRowView(
                        device: device,
                        isConnected: bleManager.connectedDevice?.id == device.id,
                        onTap: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                bleManager.connect(to: device)
                            }
                        }
                    )
                    
                    if index < devices.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Device Row View
struct DeviceRowView: View {
    let device: BLEDevice
    let isConnected: Bool
    let onTap: () -> Void
    
    var rssiStrength: (icon: String, color: Color, label: String) {
        if device.rssi > -50 {
            return ("wifi", Color(red: 0.0, green: 0.78, blue: 0.33), "Excellent")
        } else if device.rssi > -70 {
            return ("wifi", .orange, "Good")
        } else {
            return ("wifi.exclamationmark", Color(red: 1.0, green: 0.23, blue: 0.19), "Weak")
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Device Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isConnected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isConnected ? .accentColor : .secondary)
                }
                
                // Device Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: rssiStrength.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(rssiStrength.color)
                        
                        Text("\(device.rssi) dBm • \(rssiStrength.label)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Connection Indicator
                if isConnected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.78, blue: 0.33))
                            .frame(width: 8, height: 8)
                        
                        Text("Connected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.33))
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Today's Stats Section
struct TodaysStatsSection: View {
    @ObservedObject var statsManager: StatsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Text("Today's Stats")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Stats Grid
            VStack(spacing: 0) {
                // First Row
                HStack(spacing: 0) {
                    StatCard(
                        icon: "figure.bike",
                        value: String(format: "%.1f", statsManager.distanceKilometers),
                        unit: "km",
                        label: "Distance",
                        color: .blue
                    )
                    
                    Divider()
                        .frame(height: 80)
                    
                    StatCard(
                        icon: "flame.fill",
                        value: "\(statsManager.caloriesBurnt)",
                        unit: "kcal",
                        label: "Calories",
                        color: .orange
                    )
                }
                
                Divider()
                
                // Second Row
                HStack(spacing: 0) {
                    StatCard(
                        icon: "speedometer",
                        value: String(format: "%.1f", statsManager.averageSpeed),
                        unit: "km/h",
                        label: "Avg Speed",
                        color: .green
                    )
                    
                    Divider()
                        .frame(height: 80)
                    
                    StatCard(
                        icon: "timer",
                        value: formatTime(statsManager.rideTime),
                        unit: "",
                        label: "Ride Time",
                        color: .purple
                    )
                }
                
                Divider()
                
                // Third Row - Top Speed (full width)
                HStack {
                    StatCard(
                        icon: "gauge.high",
                        value: String(format: "%.1f", statsManager.topSpeed),
                        unit: "km/h",
                        label: "Top Speed",
                        color: .red,
                        isFullWidth: true
                    )
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let color: Color
    var isFullWidth: Bool = false
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(.vertical, 12)
    }
}

// MARK: - Helmet Mode Section
struct HelmetModeSection: View {
    @Binding var selectedMode: HelmetMode
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Text("Helmet Mode")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Mode Toggles - Horizontal Layout
            HStack(spacing: 12) {
                ForEach(HelmetMode.allCases, id: \.self) { mode in
                    HelmetModeButton(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        onTap: {
                            selectMode(mode)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func selectMode(_ mode: HelmetMode) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Update BLEManager with current mode FIRST (before state change)
        bleManager.setCurrentMode(mode)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedMode = mode
        }
        
        // Send mode command to Arduino when connected
        if bleManager.isConnected {
            let command = "MODE:\(mode.rawValue)"
            bleManager.send(command)
        }
    }
}

// MARK: - Helmet Mode Button
struct HelmetModeButton: View {
    let mode: HelmetMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Mode Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? mode.color.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isSelected ? mode.color : .secondary)
                }
                
                // Mode Name
                Text(mode.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? mode.color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected ? mode.color.opacity(0.08) : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? mode.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
// MARK: - Guard Mode Status Card
struct GuardModeStatusCard: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundColor(.orange)
                Text("Guard Mode Active")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            VStack(spacing: 16) {
                if let guardData = bleManager.latestGuardModeData, let lastUpdate = bleManager.lastGuardModeUpdate {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest GPS Update")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                            Text("\(String(format: "%.6f", guardData.latitude)), \(String(format: "%.6f", guardData.longitude))")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Text(timeAgo(from: lastUpdate))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.orange)
                        Text("Waiting for GPS data...")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

// MARK: - Preview
#Preview {
    // Provide simple instances for required dependencies
    let alertsManager = AlertsManager()
    let userSettings = UserSettings()
    let rideHistoryManager = RideHistoryManager()
    return ContentView(alertsManager: alertsManager, userSettings: userSettings, rideHistoryManager: rideHistoryManager)
}


