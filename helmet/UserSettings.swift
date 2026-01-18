import Foundation
import SwiftUI
import Combine

// MARK: - User Settings
class UserSettings: ObservableObject {
    @Published var name: String = ""
    @Published var phoneNumber: String = ""
    @Published var gender: String = ""
    @Published var height: String = ""
    @Published var weight: String = ""
    @Published var emergencyContactName: String = ""
    @Published var emergencyContactPhone: String = ""
    @Published var callSOSOnCrash: Bool = false
    
    private let settingsKey = "UserSettings"
    
    init() {
        loadSettings()
    }
    
    func saveSettings() {
        let settings: [String: Any] = [
            "name": name,
            "phoneNumber": phoneNumber,
            "gender": gender,
            "height": height,
            "weight": weight,
            "emergencyContactName": emergencyContactName,
            "emergencyContactPhone": emergencyContactPhone,
            "callSOSOnCrash": callSOSOnCrash
        ]
        UserDefaults.standard.set(settings, forKey: settingsKey)
    }
    
    func loadSettings() {
        if let settings = UserDefaults.standard.dictionary(forKey: settingsKey) {
            name = settings["name"] as? String ?? ""
            phoneNumber = settings["phoneNumber"] as? String ?? ""
            gender = settings["gender"] as? String ?? ""
            height = settings["height"] as? String ?? ""
            weight = settings["weight"] as? String ?? ""
            emergencyContactName = settings["emergencyContactName"] as? String ?? ""
            emergencyContactPhone = settings["emergencyContactPhone"] as? String ?? ""
            callSOSOnCrash = settings["callSOSOnCrash"] as? Bool ?? false
        }
    }
}
