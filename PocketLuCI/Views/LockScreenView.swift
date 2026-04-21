import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    let onUnlocked: () -> Void
    @State private var biometricType: LABiometryType = .none
    @State private var authError: String?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("PocketLuCI")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Unlock to continue")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let err = authError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: authenticate) {
                    Label(biometricLabel, systemImage: biometricIcon)
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .onAppear {
            let ctx = LAContext()
            ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            biometricType = ctx.biometryType
            authenticate()
        }
    }

    private var biometricLabel: String {
        switch biometricType {
        case .faceID: "Unlock with Face ID"
        case .touchID: "Unlock with Touch ID"
        default: "Unlock"
        }
    }

    private var biometricIcon: String {
        switch biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        default: "lock.open"
        }
    }

    private func authenticate() {
        authError = nil
        let ctx = LAContext()
        var pErr: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &pErr)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication
        ctx.evaluatePolicy(policy, localizedReason: "Unlock PocketLuCI") { success, err in
            DispatchQueue.main.async {
                if success {
                    onUnlocked()
                } else if let err {
                    let code = (err as? LAError)?.code
                    if code != .userCancel && code != .systemCancel {
                        authError = err.localizedDescription
                    }
                }
            }
        }
    }
}
