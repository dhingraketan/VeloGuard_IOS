import Foundation
import SwiftUI
import Combine
import MapKit
import CoreLocation

// MARK: - Alert Location
struct AlertLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var address: String?
    
    init(latitude: Double, longitude: Double, address: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Crash Severity
enum CrashSeverity: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    var color: Color {
        switch self {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .orange
        case .critical:
            return .red
        }
    }
    
    var icon: String {
        switch self {
        case .low:
            return "exclamationmark.circle.fill"
        case .medium:
            return "exclamationmark.triangle.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        }
    }
}

// MARK: - Alert Type
enum AlertType: String, Codable {
    case crashDetected = "Crash Detected"
    case helmetLeftBehind = "Helmet Left Behind"
    case possibleTheft = "Possible Theft"
    
    var icon: String {
        switch self {
        case .crashDetected:
            return "exclamationmark.triangle.fill"
        case .helmetLeftBehind:
            return "location.slash.fill"
        case .possibleTheft:
            return "hand.raised.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .crashDetected:
            return .red
        case .helmetLeftBehind:
            return .orange
        case .possibleTheft:
            return .purple
        }
    }
}

// MARK: - Alert Item
struct AlertItem: Identifiable, Codable {
    let id: UUID
    let type: AlertType
    let timestamp: Date
    let location: AlertLocation
    let additionalInfo: String
    var severity: CrashSeverity?
    var isRead: Bool
    
    init(type: AlertType, timestamp: Date, location: AlertLocation, additionalInfo: String, severity: CrashSeverity? = nil, isRead: Bool = false) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.location = location
        self.additionalInfo = additionalInfo
        self.severity = severity
        self.isRead = isRead
    }
}

// MARK: - Alerts Manager
class AlertsManager: ObservableObject {
    @Published var alerts: [AlertItem] = []
    
    private let alertsKey = "SavedAlerts"
    
    var unreadCount: Int {
        alerts.filter { !$0.isRead }.count
    }
    
    init() {
        loadAlerts()
    }
    
    func addAlert(_ alert: AlertItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.alerts.insert(alert, at: 0) // Add to beginning
            self.saveAlerts()
            print("✅ Alert added. Total alerts: \(self.alerts.count)")
        }
    }
    
    func markAsRead(_ alert: AlertItem) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            var updatedAlert = alerts[index]
            updatedAlert = AlertItem(
                type: updatedAlert.type,
                timestamp: updatedAlert.timestamp,
                location: updatedAlert.location,
                additionalInfo: updatedAlert.additionalInfo,
                severity: updatedAlert.severity,
                isRead: true
            )
            alerts[index] = updatedAlert
            saveAlerts()
        }
    }
    
    func deleteAlert(_ alert: AlertItem) {
        alerts.removeAll { $0.id == alert.id }
        saveAlerts()
    }
    
    func deleteAlert(at offsets: IndexSet) {
        alerts.remove(atOffsets: offsets)
        saveAlerts()
    }
    
    func loadAlerts() {
        if let data = UserDefaults.standard.data(forKey: alertsKey),
           let decoded = try? JSONDecoder().decode([AlertItem].self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.alerts = decoded
            }
        }
    }
    
    private func saveAlerts() {
        if let encoded = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(encoded, forKey: alertsKey)
        }
    }
}
