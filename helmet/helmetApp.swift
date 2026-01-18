//
//  helmetApp.swift
//  helmet
//
//  Created by Ketan Dhingra on 2026-01-15.
//

import SwiftUI

@main
struct helmetApp: App {
    // Shared managers - single instance for entire app
    @StateObject private var sharedAlertsManager = AlertsManager()
    @StateObject private var sharedUserSettings = UserSettings()
    @StateObject private var sharedRideHistoryManager = RideHistoryManager()
    
    var body: some Scene {
        WindowGroup {
            MainTabView(
                alertsManager: sharedAlertsManager,
                userSettings: sharedUserSettings,
                rideHistoryManager: sharedRideHistoryManager
            )
        }
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @ObservedObject var alertsManager: AlertsManager
    @ObservedObject var userSettings: UserSettings
    @ObservedObject var rideHistoryManager: RideHistoryManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView(
                alertsManager: alertsManager,
                userSettings: userSettings,
                rideHistoryManager: rideHistoryManager
            )
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }
            .tag(0)
            
            RideHistoryView(rideHistoryManager: rideHistoryManager)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)
            
            AlertsView(alertsManager: alertsManager)
                .tabItem {
                    Label("Alerts", systemImage: "bell.fill")
                }
                .tag(2)
            
            SettingsView(userSettings: userSettings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.accentColor)
    }
}
