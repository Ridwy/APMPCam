import AVFoundation
import VideoToolbox
import CoreMedia

final class CameraManager: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "camera.manager.queue")
    private var _isRecording = false
    private var isRecording: Bool {
        get { queue.sync { _isRecording } }
        set { queue.sync { _isRecording = newValue } }
    }

    let captureSession = AVCaptureSession()
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var currentIntrinsics: matrix_float3x3?
    private var currentImageSize: CGSize?
    private let videoQueue = DispatchQueue(label: "video.queue")

    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else {
            print("Ultra wide camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: videoQueue)
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
            }
            
            if let connection = output.connection(with: .video) {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
                
                // Disable video stabilization (expected wider angle but not much difference)
//                if connection.isVideoStabilizationSupported {
//                    connection.preferredVideoStabilizationMode = .off
//                    print("Video stabilization disabled on connection")
//                }
            }
            
            try camera.lockForConfiguration()
            // Enable geometric distortion correction (default is true)
            camera.isGeometricDistortionCorrectionEnabled = true
            
            camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
            
            if let format = selectBestFormat(for: camera) {
                camera.activeFormat = format
            }
            camera.unlockForConfiguration()
            
        } catch {
            print("Failed to setup camera: \(error)")
        }
        
        captureSession.commitConfiguration()
    }
    
    private func selectBestFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = device.formats

        // Find maximum FOV first
        guard let maxFoV = formats.map(\.videoFieldOfView).max() else { return nil }
        let maxFoVFormats = formats.filter { $0.videoFieldOfView == maxFoV }

        // Among max FOV formats, find maximum resolution
        guard let maxWidth = maxFoVFormats
            .map({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width })
            .max() else { return maxFoVFormats.first }

        var finalFormats = maxFoVFormats
            .filter { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width == maxWidth }

        // Prefer 420v format if available
        let _420vFormats = finalFormats.filter {
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == 875704438
        }

        if !_420vFormats.isEmpty {
            finalFormats = _420vFormats
        }

        // Filter to only formats with the highest frame rate
        let maxFps = finalFormats
            .flatMap { $0.videoSupportedFrameRateRanges.map(\.maxFrameRate) }
            .max() ?? 0

        if maxFps > 0 {
            finalFormats = finalFormats.filter { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate == maxFps }
            }
        }
        
        // Log details of final format candidates
        print("=== Final Format Candidates ===")
        for (index, format) in finalFormats.enumerated() {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let frameRates = format.videoSupportedFrameRateRanges
            let pixelFormatType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let pixelFormatString = String(format: "%c%c%c%c",
                                          UInt8((pixelFormatType >> 24) & 0xff),
                                          UInt8((pixelFormatType >> 16) & 0xff),
                                          UInt8((pixelFormatType >> 8) & 0xff),
                                          UInt8(pixelFormatType & 0xff))

            print("Format \(index):")
            print("  Resolution: \(dimensions.width) x \(dimensions.height)")
            print("  FOV: \(format.videoFieldOfView)°")
            print("  HDR: \(format.isVideoHDRSupported)")
            print("  Pixel Format: \(pixelFormatString)")
            print("  Frame Rate Ranges:")
            for range in frameRates {
                print("    \(range.minFrameRate) - \(range.maxFrameRate) fps")
            }
            print("  Binned: \(format.isVideoBinned)")
            print("  Stabilization Supported: \(format.isVideoStabilizationModeSupported(.standard))")
        }
        print("===============================")

        return finalFormats.last
    }
    
    func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func startRecording() -> Bool {
        return queue.sync {
            guard !_isRecording else { return false }
            guard let imageSize = currentImageSize, let intrinsics = currentIntrinsics else { return false }

            let documentsPath = NSTemporaryDirectory()
            let outputPath = (documentsPath as NSString).appendingPathComponent("video_\(Int(Date().timeIntervalSince1970)).mov")
            let outputURL = URL(fileURLWithPath: outputPath)

            do {
                assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

                let compressionProperties = WideFOVMetadata.createCompressionPropertiesFromIntrinsicMatrix(intrinsics, imageSize: imageSize)
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Int(imageSize.width),
                    AVVideoHeightKey: Int(imageSize.height),
                    AVVideoCompressionPropertiesKey: compressionProperties
                ]

                assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                assetWriterInput?.expectsMediaDataInRealTime = true

                if let input = assetWriterInput, assetWriter?.canAdd(input) == true {
                    assetWriter?.add(input)
                }

                startTime = nil
                _isRecording = true

                return true

            } catch {
                print("Failed to start recording: \(error)")
                return false
            }
        }
    }
    
    func stopRecording() async -> Bool {
        let (writerInput, writer) = queue.sync { () -> (AVAssetWriterInput?, AVAssetWriter?) in
            guard _isRecording else { return (nil, nil) }
            _isRecording = false
            return (assetWriterInput, assetWriter)
        }

        guard let assetWriterInput = writerInput, let assetWriter = writer else { return false }

        assetWriterInput.markAsFinished()
        let outputURL = assetWriter.outputURL
        await assetWriter.finishWriting()

        PhotoLibraryUtility.saveVideoToPhotoLibrary(url: outputURL)

        queue.sync {
            self.assetWriter = nil
            self.assetWriterInput = nil
            self.startTime = nil
        }

        return true
    }
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Cache intrinsics for future recording sessions
        if currentIntrinsics == nil,
           let intrinsics = extractIntrinsics(from: sampleBuffer),
           let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let imageSize = CGSize(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
            queue.sync {
                currentIntrinsics = intrinsics
                currentImageSize = imageSize
            }
            logIntrinsics(intrinsics, imageSize: imageSize)
        }

        queue.sync {
            guard _isRecording else { return }

            if startTime == nil {
                startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                assetWriter?.startWriting()
                assetWriter?.startSession(atSourceTime: CMTime.zero)
            }

            if assetWriterInput?.isReadyForMoreMediaData == true {
                // Adjust timestamp to start from zero
                let currentPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let adjustedPTS = CMTimeSubtract(currentPTS, startTime!)

                // Create adjusted sample buffer
                var timingInfo = CMSampleTimingInfo(
                    duration: CMSampleBufferGetDuration(sampleBuffer),
                    presentationTimeStamp: adjustedPTS,
                    decodeTimeStamp: CMTime.invalid
                )

                var adjustedSampleBuffer: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timingInfo,
                    sampleBufferOut: &adjustedSampleBuffer
                )

                if let adjustedBuffer = adjustedSampleBuffer {
                    assetWriterInput?.append(adjustedBuffer)
                }
            }
        }
    }

}

extension CameraManager {
    private func extractIntrinsics(from sampleBuffer: CMSampleBuffer) -> matrix_float3x3? {
        guard let cameraIntrinsicMatrix = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else {
            return nil
        }
        
        let matrix = cameraIntrinsicMatrix.withUnsafeBytes { bytes in
            bytes.bindMemory(to: matrix_float3x3.self).baseAddress?.pointee
        }
        
        return matrix
    }

    private func logIntrinsics(_ intrinsics: matrix_float3x3, imageSize: CGSize) {
        print("=== Camera Intrinsics ===")
        print("Image Size: \(Int(imageSize.width)) x \(Int(imageSize.height))")
        print("Intrinsic Matrix:")
        print("  fx: \(intrinsics[0][0])")
        print("  fy: \(intrinsics[1][1])")
        print("  cx: \(intrinsics[2][0])")
        print("  cy: \(intrinsics[2][1])")
        
        // Calculate FOV
        let horizontalFOV = 2.0 * atan(Float(imageSize.width) / (2.0 * intrinsics[0][0])) * 180.0 / Float.pi
        let verticalFOV = 2.0 * atan(Float(imageSize.height) / (2.0 * intrinsics[1][1])) * 180.0 / Float.pi
        print("Field of View:")
        print("  Horizontal: \(horizontalFOV)°")
        print("  Vertical: \(verticalFOV)°")
        print("========================")
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processSampleBuffer(sampleBuffer)
    }
}
