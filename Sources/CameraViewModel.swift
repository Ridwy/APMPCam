import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    @Published var isRecording = false
    let cameraManager = CameraManager()

    func startSession() {
        cameraManager.startSession()
    }

    func stopSession() {
        cameraManager.stopSession()
    }

    func startRecording() {
        let success = cameraManager.startRecording()
        if success {
            isRecording = true
        }
    }

    func stopRecording() {
        Task { [cameraManager] in
            let success = await cameraManager.stopRecording()
            await MainActor.run {
                if success {
                    isRecording = false
                }
            }
        }
    }
}
