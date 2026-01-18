import SwiftUI
import MapKit

struct AlertsView: View {
    @ObservedObject var alertsManager: AlertsManager
    @State private var selectedAlert: AlertItem?
    
    var body: some View {
        NavigationStack {
            Group {
                if alertsManager.alerts.isEmpty {
                    EmptyAlertsView()
                } else {
                    List {
                        ForEach(alertsManager.alerts) { alert in
                            AlertRowView(alert: alert)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedAlert = alert
                                    alertsManager.markAsRead(alert)
                                }
                        }
                        .onDelete(perform: alertsManager.deleteAlert)
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        alertsManager.loadAlerts()
                    }
                }
            }
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedAlert) { alert in
                AlertDetailView(alert: alert, alertsManager: alertsManager)
            }
            .onAppear {
                alertsManager.loadAlerts()
            }
        }
    }
}

// MARK: - Empty Alerts View
struct EmptyAlertsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Alerts")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("You're all caught up!")
                .font(.system(size: 17))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alert Row View
struct AlertRowView: View {
    let alert: AlertItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Alert Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(alert.type.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: alert.type.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(alert.type.color)
            }
            
            // Alert Info
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.type.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(alert.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                if let severity = alert.severity {
                    HStack(spacing: 4) {
                        Image(systemName: severity.icon)
                            .font(.system(size: 11))
                            .foregroundColor(severity.color)
                        
                        Text(severity.rawValue)
                            .font(.system(size: 13))
                            .foregroundColor(severity.color)
                    }
                }
            }
            
            Spacer()
            
            // Unread Indicator
            if !alert.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Alert Detail View
struct AlertDetailView: View {
    let alert: AlertItem
    @ObservedObject var alertsManager: AlertsManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(alert.type.color.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: alert.type.icon)
                                .font(.system(size: 40))
                                .foregroundColor(alert.type.color)
                        }
                        
                        Text(alert.type.rawValue)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(alert.timestamp.formatted(date: .complete, time: .standard))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top)
                    
                    // Severity (if crash)
                    if let severity = alert.severity {
                        HStack {
                            Image(systemName: severity.icon)
                                .foregroundColor(severity.color)
                            Text("Severity: \(severity.rawValue)")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(severity.color)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(severity.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Map
                    if alert.location.latitude != 0.0 || alert.location.longitude != 0.0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Map(coordinateRegion: .constant(MKCoordinateRegion(
                                center: alert.location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )), annotationItems: [MapAnnotationItem(coordinate: alert.location.coordinate)]) { item in
                                MapMarker(coordinate: item.coordinate, tint: alert.type.color)
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // Additional Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(alert.additionalInfo)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Coordinates
                    if alert.location.latitude != 0.0 || alert.location.longitude != 0.0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coordinates")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("Latitude: \(String(format: "%.6f", alert.location.latitude))")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                            
                            Text("Longitude: \(String(format: "%.6f", alert.location.longitude))")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Alert Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Map Annotation Item
struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    let alertsManager = AlertsManager()
    return AlertsView(alertsManager: alertsManager)
}
