import Foundation
import CoreLocation
import Combine

// MARK: - GPS Point
struct GPSPoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitude: Double?
    
    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.altitude = location.altitude > 0 ? location.altitude : nil
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Pothole Event
struct PotholeEvent: Codable {
    let timestamp: Date
    let location: GPSPoint?
    let severity: String? // Optional severity from Arduino
    
    init(timestamp: Date, location: GPSPoint? = nil, severity: String? = nil) {
        self.timestamp = timestamp
        self.location = location
        self.severity = severity
    }
}

// MARK: - Ride Data Tracker
class RideDataTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isTracking: Bool = false
    @Published var gpsPoints: [GPSPoint] = []
    @Published var potholeEvents: [PotholeEvent] = []
    
    private var locationManager = CLLocationManager()
    private var startTime: Date?
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0 // Update every 5 meters
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        guard !isTracking else { return }
        
        print("🚴 Starting ride tracking...")
        isTracking = true
        startTime = Date()
        gpsPoints.removeAll()
        potholeEvents.removeAll()
        
        // Request location authorization if needed
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        // Start location updates
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
            print("✅ Location tracking started")
        } else {
            print("❌ Location services not enabled")
        }
    }
    
    func stopTracking() {
        guard isTracking else { return }
        
        print("🛑 Stopping ride tracking...")
        isTracking = false
        locationManager.stopUpdatingLocation()
        
        print("📊 Ride data collected:")
        print("   GPS Points: \(gpsPoints.count)")
        print("   Pothole Events: \(potholeEvents.count)")
    }
    
    func addPotholeEvent(severity: String? = nil) {
        guard isTracking else { return }
        
        let location = lastLocation != nil ? GPSPoint(location: lastLocation!) : nil
        let event = PotholeEvent(timestamp: Date(), location: location, severity: severity)
        potholeEvents.append(event)
        
        print("🕳️ Pothole detected at: \(event.timestamp.formatted(date: .omitted, time: .standard))")
        if let loc = location {
            print("   Location: \(loc.latitude), \(loc.longitude)")
        }
    }
    
    func getRideData() -> (gpsPoints: [GPSPoint], potholeEvents: [PotholeEvent], startTime: Date?) {
        return (gpsPoints, potholeEvents, startTime)
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let location = locations.last else { return }
        
        // Only add if location is valid
        guard location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 else {
            print("⚠️ Invalid location accuracy: \(location.horizontalAccuracy)")
            return
        }
        
        lastLocation = location
        let gpsPoint = GPSPoint(location: location)
        gpsPoints.append(gpsPoint)
        
        // Log every 10th point to avoid spam
        if gpsPoints.count % 10 == 0 {
            print("📍 GPS point \(gpsPoints.count): \(gpsPoint.latitude), \(gpsPoint.longitude)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isTracking {
                locationManager.startUpdatingLocation()
            }
        case .denied, .restricted:
            print("❌ Location authorization denied")
        case .notDetermined:
            print("❓ Location authorization not determined")
        @unknown default:
            break
        }
    }
}
