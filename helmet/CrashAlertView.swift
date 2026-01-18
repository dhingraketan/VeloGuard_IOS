import SwiftUI

struct CrashAlertView: View {
    @ObservedObject var crashWorkflowManager: CrashWorkflowManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Warning Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                }
                .padding(.top, 20)
                
                // Title
                Text("Crash Detected!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                
                // Description
                VStack(spacing: 8) {
                    Text("A crash has been detected by your helmet.")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Emergency services will be contacted in \(crashWorkflowManager.timeRemaining) seconds.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    // Cancel Button
                    Button(action: {
                        crashWorkflowManager.cancelCrashAlert()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Proceed Button
                    Button(action: {
                        crashWorkflowManager.proceedWithCrashAlert()
                        dismiss()
                    }) {
                        Text("Proceed")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        crashWorkflowManager.cancelCrashAlert()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CrashAlertView(crashWorkflowManager: CrashWorkflowManager())
}
