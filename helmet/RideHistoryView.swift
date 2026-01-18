import SwiftUI
import MapKit
import Combine

struct RideHistoryView: View {
    @ObservedObject var rideHistoryManager: RideHistoryManager
    @State private var selectedRide: Ride?
    
    var body: some View {
        NavigationStack {
            Group {
                if rideHistoryManager.rides.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(rideHistoryManager.rides) { ride in
                            RideRowView(ride: ride)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRide = ride
                                }
                        }
                        .onDelete(perform: rideHistoryManager.deleteRide)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Ride History")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedRide) { ride in
                RideDetailView(ride: ride)
            }
        }
    }
}

// MARK: - Ride Row View
struct RideRowView: View {
    let ride: Ride
    
    var body: some View {
        HStack(spacing: 12) {
            // Ride Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "bicycle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            // Ride Info
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Label("\(String(format: "%.1f", ride.distanceKilometers)) km", systemImage: "bicycle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Label("\(ride.caloriesBurnt) kcal", systemImage: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(formatTime(ride.timeTaken))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
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

// MARK: - Ride Detail View
struct RideDetailView: View {
    let ride: Ride
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "bicycle")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                        
                        Text(ride.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(ride.date.formatted(date: .complete, time: .standard))
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top)
                    
                    // Stats Grid
                    VStack(spacing: 12) {
                        StatItem(icon: "bicycle", label: "Distance", value: "\(String(format: "%.1f", ride.distanceKilometers)) km", color: .blue)
                        StatItem(icon: "flame.fill", label: "Calories", value: "\(ride.caloriesBurnt) kcal", color: .orange)
                        StatItem(icon: "clock.fill", label: "Time", value: formatTime(ride.timeTaken), color: .purple)
                        StatItem(icon: "mountain.2.fill", label: "Altitude", value: "\(String(format: "%.0f", ride.altitudeCovered)) m", color: .green)
                        StatItem(icon: "star.fill", label: "Smoothness", value: "\(String(format: "%.1f", ride.smoothnessScore))/10", color: .yellow)
                    }
                    
                    // Map
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if !ride.routeCoordinates.isEmpty {
                            MapViewWithPolyline(coordinates: ride.routeCoordinates, region: calculateRegion())
                                .frame(height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Map(coordinateRegion: .constant(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )))
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                Text("Route data not available")
                                    .foregroundColor(.secondary)
                            )
                        }
                    }
                    
                    // Ride Analysis Summary (Placeholder)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ride Analysis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Ride analysis summary will be implemented here.")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Ride Details")
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
    
    private func calculateRegion() -> MKCoordinateRegion {
        guard !ride.routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        let minLat = ride.routeCoordinates.map { $0.latitude }.min() ?? 0
        let maxLat = ride.routeCoordinates.map { $0.latitude }.max() ?? 0
        let minLon = ride.routeCoordinates.map { $0.longitude }.min() ?? 0
        let maxLon = ride.routeCoordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.01)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        DetailStatCard(icon: icon, label: label, value: value, color: color)
    }
}

// MARK: - Detail Stat Card
struct DetailStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Rides Yet")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Your ride history will appear here")
                .font(.system(size: 17))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Map View With Polyline
struct MapViewWithPolyline: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        
        // Add polyline overlay
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: false)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#Preview {
    RideHistoryView(rideHistoryManager: RideHistoryManager())
}
