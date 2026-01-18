import Foundation
import CoreLocation

// MARK: - Gemini API Response Models
struct GeminiResponse: Codable {
    let candidates: [Candidate]?
    let error: ErrorResponse?
    
    struct Candidate: Codable {
        let content: Content
        
        struct Content: Codable {
            let parts: [Part]
            
            struct Part: Codable {
                let text: String
            }
        }
    }
    
    struct ErrorResponse: Codable {
        let code: Int?
        let message: String?
        let status: String?
    }
}

// MARK: - Ride Analysis Result
struct RideAnalysis: Codable {
    let rideName: String
    let distanceKilometers: Double
    let altitudeCovered: Double
    let averageSpeed: Double
    let topSpeed: Double
    let rideScore: Double
    let summary: String
    let tips: [String]
}

// MARK: - Gemini Service
class GeminiService {
    private let apiKey: String
    // Use v1beta API with gemini-2.5-flash (gemini-1.5-flash is deprecated)
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func analyzeRide(
        gpsPoints: [GPSPoint],
        potholeEvents: [PotholeEvent],
        startTime: Date?,
        completion: @escaping (Result<RideAnalysis, Error>) -> Void
    ) {
        print("🤖 Calling Gemini API for ride analysis...")
        
        // Calculate basic stats
        let distance = calculateDistance(from: gpsPoints)
        let altitude = calculateAltitude(from: gpsPoints)
        let speeds = calculateSpeeds(from: gpsPoints)
        let avgSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(0, +) / Double(speeds.count)
        let topSpeed = speeds.max() ?? 0.0
        let duration = calculateDuration(gpsPoints: gpsPoints, startTime: startTime)
        
        // Create prompt
        let prompt = createPrompt(
            gpsPoints: gpsPoints,
            potholeEvents: potholeEvents,
            distance: distance,
            altitude: altitude,
            avgSpeed: avgSpeed,
            topSpeed: topSpeed,
            duration: duration
        )
        
        // Make API request
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Gemini API error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
             // Decode and parse off the main actor, then hop to main for completion
             Task.detached {
                 do {
                     let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
                     
                     // Check for API errors first
                     if let error = geminiResponse.error {
                         let errorMessage = error.message ?? "Unknown error"
                         let errorCode = error.code ?? -1
                         print("❌ Gemini API error: \(errorMessage) (code: \(errorCode))")
                         await MainActor.run {
                             completion(.failure(NSError(domain: "GeminiService", code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                         }
                         return
                     }
                     
                     // Check for candidates
                     guard let candidates = geminiResponse.candidates, !candidates.isEmpty else {
                         print("❌ No candidates in Gemini response")
                         await MainActor.run {
                             completion(.failure(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response candidates"])))
                         }
                         return
                     }
                     
                     if let text = candidates.first?.content.parts.first?.text {
                         print("✅ Received Gemini response")
                         let analysis = try self.parseGeminiResponse(
                             text: text,
                             distance: distance,
                             altitude: altitude,
                             avgSpeed: avgSpeed,
                             topSpeed: topSpeed
                         )
                         await MainActor.run {
                             completion(.success(analysis))
                         }
                     } else {
                         await MainActor.run {
                             completion(.failure(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response text"])))
                         }
                     }
                 } catch {
                     print("❌ Failed to parse Gemini response: \(error)")
                     print("Response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                     await MainActor.run {
                         completion(.failure(error))
                     }
                 }
             }
        }.resume()
    }
    
    private func createPrompt(
        gpsPoints: [GPSPoint],
        potholeEvents: [PotholeEvent],
        distance: Double,
        altitude: Double,
        avgSpeed: Double,
        topSpeed: Double,
        duration: TimeInterval
    ) -> String {
        let potholeCount = potholeEvents.count
        let smoothnessScore = calculateSmoothnessScore(potholeCount: potholeCount, distance: distance)
        
        return """
        You are a cycling analysis expert. Analyze the following bike ride data and provide a comprehensive analysis in JSON format.
        
        Ride Statistics:
        - Distance: \(String(format: "%.2f", distance)) km
        - Altitude covered: \(String(format: "%.0f", altitude)) meters
        - Average speed: \(String(format: "%.1f", avgSpeed)) km/h
        - Top speed: \(String(format: "%.1f", topSpeed)) km/h
        - Duration: \(formatDuration(duration))
        - Potholes detected: \(potholeCount)
        - Smoothness score: \(String(format: "%.1f", smoothnessScore))/10
        
        GPS Points: \(gpsPoints.count) points recorded
        Pothole Events: \(potholeEvents.count) events
        
        Please provide a JSON response with the following structure:
        {
            "rideName": "A creative, short name for this ride (max 3-4 words)",
            "distanceKilometers": \(distance),
            "altitudeCovered": \(altitude),
            "averageSpeed": \(avgSpeed),
            "topSpeed": \(topSpeed),
            "rideScore": \(smoothnessScore),
            "summary": "A 2-3 sentence summary of the ride highlighting key aspects",
            "tips": ["Tip 1 for improvement", "Tip 2 for improvement", "Tip 3 for improvement"]
        }
        
        The rideName should be creative and descriptive based on the ride characteristics (e.g., "Morning Commute", "Mountain Challenge", "City Explorer").
        The summary should highlight the ride's key characteristics, performance, and any notable events.
        The tips should be practical and actionable suggestions for improving future rides.
        
        Return ONLY valid JSON, no additional text or markdown formatting.
        """
    }
    
    private func parseGeminiResponse(
        text: String,
        distance: Double,
        altitude: Double,
        avgSpeed: Double,
        topSpeed: Double
    ) throws -> RideAnalysis {
        // Clean the response text (remove markdown code blocks if present)
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = cleanedText.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedText.hasPrefix("```") {
            cleanedText = cleanedText.replacingOccurrences(of: "```", with: "")
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasSuffix("```") {
            cleanedText = String(cleanedText.dropLast(3))
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedText.data(using: .utf8) else {
            throw NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert text to data"])
        }
        
        do {
            let analysis = try JSONDecoder().decode(RideAnalysis.self, from: data)
            return analysis
        } catch {
            // If parsing fails, create a fallback analysis
            print("⚠️ Failed to parse JSON, creating fallback analysis")
            return RideAnalysis(
                rideName: "Bike Ride",
                distanceKilometers: distance,
                altitudeCovered: altitude,
                averageSpeed: avgSpeed,
                topSpeed: topSpeed,
                rideScore: calculateSmoothnessScore(potholeCount: 0, distance: distance),
                summary: "A great ride! Keep up the good work.",
                tips: [
                    "Maintain consistent speed",
                    "Watch for potholes",
                    "Stay hydrated"
                ]
            )
        }
    }
    
    // MARK: - Helper Functions
    private func calculateDistance(from points: [GPSPoint]) -> Double {
        guard points.count >= 2 else { return 0.0 }
        
        var totalDistance: Double = 0.0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            totalDistance += prev.distance(from: curr)
        }
        
        return totalDistance / 1000.0 // Convert to kilometers
    }
    
    private func calculateAltitude(from points: [GPSPoint]) -> Double {
        guard !points.isEmpty else { return 0.0 }
        
        let altitudes = points.compactMap { $0.altitude }
        guard !altitudes.isEmpty else { return 0.0 }
        
        let minAlt = altitudes.min() ?? 0.0
        let maxAlt = altitudes.max() ?? 0.0
        
        return max(0, maxAlt - minAlt)
    }
    
    private func calculateSpeeds(from points: [GPSPoint]) -> [Double] {
        guard points.count >= 2 else { return [] }
        
        var speeds: [Double] = []
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            
            let distance = prev.distance(from: curr) // meters
            let timeInterval = points[i].timestamp.timeIntervalSince(points[i-1].timestamp) // seconds
            
            if timeInterval > 0 {
                let speed = (distance / timeInterval) * 3.6 // Convert to km/h
                speeds.append(speed)
            }
        }
        
        return speeds
    }
    
    private func calculateDuration(gpsPoints: [GPSPoint], startTime: Date?) -> TimeInterval {
        if let start = startTime, let end = gpsPoints.last?.timestamp {
            return end.timeIntervalSince(start)
        } else if gpsPoints.count >= 2 {
            return gpsPoints.last!.timestamp.timeIntervalSince(gpsPoints.first!.timestamp)
        }
        return 0
    }
    
    private func calculateSmoothnessScore(potholeCount: Int, distance: Double) -> Double {
        guard distance > 0 else { return 10.0 }
        
        let potholesPerKm = Double(potholeCount) / distance
        let score = max(0.0, min(10.0, 10.0 - (potholesPerKm * 2.0)))
        
        return Double(round(score * 10) / 10) // Round to 1 decimal place
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
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

