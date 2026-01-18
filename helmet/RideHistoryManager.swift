import Foundation
import SwiftUI
import Combine
import MapKit
import CoreLocation

// MARK: - Ride Model
struct Ride: Identifiable, Codable {
    let id: UUID
    let title: String
    let date: Date
    let distanceKilometers: Double
    let caloriesBurnt: Int
    let timeTaken: TimeInterval
    let altitudeCovered: Double
    let smoothnessScore: Double
    let routeCoordinates: [CLLocationCoordinate2D]
    let averageSpeed: Double
    let topSpeed: Double
    let rideScore: Double
    let summary: String?
    let tips: [String]?
    
    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        distanceKilometers: Double,
        caloriesBurnt: Int,
        timeTaken: TimeInterval,
        altitudeCovered: Double,
        smoothnessScore: Double,
        routeCoordinates: [CLLocationCoordinate2D] = [],
        averageSpeed: Double = 0.0,
        topSpeed: Double = 0.0,
        rideScore: Double = 0.0,
        summary: String? = nil,
        tips: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.distanceKilometers = distanceKilometers
        self.caloriesBurnt = caloriesBurnt
        self.timeTaken = timeTaken
        self.altitudeCovered = altitudeCovered
        self.smoothnessScore = smoothnessScore
        self.routeCoordinates = routeCoordinates
        self.averageSpeed = averageSpeed
        self.topSpeed = topSpeed
        self.rideScore = rideScore
        self.summary = summary
        self.tips = tips
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, date, distanceKilometers, caloriesBurnt, timeTaken, altitudeCovered, smoothnessScore
        case routeLatitudes, routeLongitudes, averageSpeed, topSpeed, rideScore, summary, tips
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        distanceKilometers = try container.decode(Double.self, forKey: .distanceKilometers)
        caloriesBurnt = try container.decode(Int.self, forKey: .caloriesBurnt)
        timeTaken = try container.decode(TimeInterval.self, forKey: .timeTaken)
        altitudeCovered = try container.decode(Double.self, forKey: .altitudeCovered)
        smoothnessScore = try container.decode(Double.self, forKey: .smoothnessScore)
        averageSpeed = try container.decodeIfPresent(Double.self, forKey: .averageSpeed) ?? 0.0
        topSpeed = try container.decodeIfPresent(Double.self, forKey: .topSpeed) ?? 0.0
        rideScore = try container.decodeIfPresent(Double.self, forKey: .rideScore) ?? smoothnessScore
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        tips = try container.decodeIfPresent([String].self, forKey: .tips)
        
        let lats = try container.decode([Double].self, forKey: .routeLatitudes)
        let lons = try container.decode([Double].self, forKey: .routeLongitudes)
        routeCoordinates = zip(lats, lons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encode(distanceKilometers, forKey: .distanceKilometers)
        try container.encode(caloriesBurnt, forKey: .caloriesBurnt)
        try container.encode(timeTaken, forKey: .timeTaken)
        try container.encode(altitudeCovered, forKey: .altitudeCovered)
        try container.encode(smoothnessScore, forKey: .smoothnessScore)
        try container.encode(averageSpeed, forKey: .averageSpeed)
        try container.encode(topSpeed, forKey: .topSpeed)
        try container.encode(rideScore, forKey: .rideScore)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(tips, forKey: .tips)
        try container.encode(routeCoordinates.map { $0.latitude }, forKey: .routeLatitudes)
        try container.encode(routeCoordinates.map { $0.longitude }, forKey: .routeLongitudes)
    }
}

// MARK: - Ride History Manager
class RideHistoryManager: ObservableObject {
    @Published var rides: [Ride] = []
    
    private let ridesKey = "SavedRides"
    
    init() {
        loadRides()
    }
    
    func addRide(_ ride: Ride) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rides.insert(ride, at: 0) // Add to beginning
            self.saveRides()
        }
    }
    
    func deleteRide(_ ride: Ride) {
        rides.removeAll { $0.id == ride.id }
        saveRides()
    }
    
    func deleteRide(at offsets: IndexSet) {
        rides.remove(atOffsets: offsets)
        saveRides()
    }
    
    func loadRides() {
        if let data = UserDefaults.standard.data(forKey: ridesKey),
           let decoded = try? JSONDecoder().decode([Ride].self, from: data) {
            DispatchQueue.main.async { [weak self] in
                self?.rides = decoded
            }
        } else {
            // Load sample data for demo
            loadSampleRides()
        }
    }
    
    private func loadSampleRides() {
        let sampleRides = [
            Ride(
                title: "Morning Ride",
                date: Date().addingTimeInterval(-86400), // Yesterday
                distanceKilometers: 15.3,
                caloriesBurnt: 420,
                timeTaken: 3600, // 1 hour
                altitudeCovered: 150.0,
                smoothnessScore: 8.5
            ),
            Ride(
                title: "Evening Commute",
                date: Date().addingTimeInterval(-172800), // 2 days ago
                distanceKilometers: 8.7,
                caloriesBurnt: 245,
                timeTaken: 2100, // 35 minutes
                altitudeCovered: 75.0,
                smoothnessScore: 7.2
            ),
            Ride(
                title: "Weekend Adventure",
                date: Date().addingTimeInterval(-259200), // 3 days ago
                distanceKilometers: 32.1,
                caloriesBurnt: 890,
                timeTaken: 7200, // 2 hours
                altitudeCovered: 320.0,
                smoothnessScore: 9.1
            )
        ]
        rides = sampleRides
        saveRides()
    }
    
    func saveRides() {
        if let encoded = try? JSONEncoder().encode(rides) {
            UserDefaults.standard.set(encoded, forKey: ridesKey)
        }
    }
    
    func updateRide(_ ride: Ride) {
        if let index = rides.firstIndex(where: { $0.id == ride.id }) {
            rides[index] = ride
            saveRides()
        }
    }
}
