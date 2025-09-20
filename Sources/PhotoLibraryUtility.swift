import Photos
import Foundation

class PhotoLibraryUtility {
    static func saveVideoToPhotoLibrary(url: URL) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized else {
                print("Photo library access denied")
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                print("Video saved to photo library")
            } catch {
                print("Failed to save video: \(error)")
            }

            try? FileManager.default.removeItem(at: url)
        }
    }
}