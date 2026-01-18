import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var userSettings: UserSettings
    @State private var isEditing = false
    @State private var showSaveConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                // User Info Section
                Section {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        TextField("Name", text: $userSettings.name)
                            .disabled(!isEditing)
                    }
                    
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        TextField("Phone Number", text: $userSettings.phoneNumber)
                            .keyboardType(.phonePad)
                            .disabled(!isEditing)
                    }
                    
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        TextField("Gender", text: $userSettings.gender)
                            .disabled(!isEditing)
                    }
                    
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        TextField("Height (cm)", text: $userSettings.height)
                            .keyboardType(.decimalPad)
                            .disabled(!isEditing)
                    }
                    
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        TextField("Weight (kg)", text: $userSettings.weight)
                            .keyboardType(.decimalPad)
                            .disabled(!isEditing)
                    }
                } header: {
                    Text("User Info")
                } footer: {
                    Text("Your personal information helps personalize your experience.")
                }
                
                // Emergency Contact Section
                Section {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.exclamationmark.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        
                        TextField("Name", text: $userSettings.emergencyContactName)
                            .disabled(!isEditing)
                    }
                    
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        
                        TextField("Phone Number", text: $userSettings.emergencyContactPhone)
                            .keyboardType(.phonePad)
                            .disabled(!isEditing)
                    }
                } header: {
                    Text("Emergency Contact Details")
                } footer: {
                    Text("This contact will be notified in case of an emergency.")
                }
                
                // Safety Settings Section
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        Toggle("Call SOS on Crash", isOn: $userSettings.callSOSOnCrash)
                            .disabled(!isEditing)
                    }
                } header: {
                    Text("Safety Settings")
                } footer: {
                    Text("Automatically call emergency services when a crash is detected.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveSettings()
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    } else {
                        Button("Edit") {
                            withAnimation {
                                isEditing = true
                            }
                        }
                    }
                }
                
                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            cancelEditing()
                        }
                    }
                }
            }
            .alert("Settings Saved", isPresented: $showSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your settings have been saved successfully.")
            }
        }
    }
    
    private func saveSettings() {
        userSettings.saveSettings()
        isEditing = false
        showSaveConfirmation = true
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func cancelEditing() {
        userSettings.loadSettings()
        withAnimation {
            isEditing = false
        }
    }
}

#Preview {
    SettingsView(userSettings: UserSettings())
}
