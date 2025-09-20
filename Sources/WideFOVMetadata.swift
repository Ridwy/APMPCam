import AVFoundation
import VideoToolbox
import simd

struct WideFOVMetadata {
    
    // MARK: - Lens Collection from Intrinsic Matrix
    private static func createLensCollectionFromIntrinsicMatrix(_ intrinsicMatrix: matrix_float3x3, imageSize: CGSize) -> [[CFString: Any]] {
        var lensCollection: [[CFString: Any]] = []
        
        // lnhd Wide FOV lens configuration
        var lensConfig: [CFString: Any] = [
            kVTCompressionPropertyCameraCalibrationKey_LensAlgorithmKind: kVTCameraCalibrationLensAlgorithmKind_ParametricLens,
            kVTCompressionPropertyCameraCalibrationKey_LensDomain: kVTCameraCalibrationLensDomain_Color,
            kVTCompressionPropertyCameraCalibrationKey_LensIdentifier: 0,
            kVTCompressionPropertyCameraCalibrationKey_LensRole: kVTCameraCalibrationLensRole_Mono
        ]
        
        // rdim: Reference dimensions
        let dimensionsDict = [
            "Width": Float(imageSize.width),
            "Height": Float(imageSize.height)
        ]
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrixReferenceDimensions] = dimensionsDict
        
        // lnin: Intrinsic matrix K
        var matrixCopy = intrinsicMatrix
        let intrinsicMatrixData = Data(bytes: &matrixCopy, count: MemoryLayout<matrix_float3x3>.size)
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrix] = intrinsicMatrixData
        
        // ξ parameter
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_IntrinsicMatrixProjectionOffset] = 0  // Pinhole
        
        /*
        // ldst (Optional): Brown-Conrady distortion model k1, k2, p1, p2
        let defaultDistortions: [Float] = [0.0, 0.0, 0.0, 0.0] // No distortion
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_LensDistortions] = defaultDistortions
        
        // Radial angle limit for Brown-Conrady model, extrapolated beyond this range
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_RadialAngleLimit] = 90.0
        
        // lfad (Optional): Frame adjustments
        let defaultPolynomialX = [0.0, 1.0, 0.0] // No adjustment
        let defaultPolynomialY = [0.0, 1.0, 0.0]
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_LensFrameAdjustmentsPolynomialX] = defaultPolynomialX
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_LensFrameAdjustmentsPolynomialY] = defaultPolynomialY
        
        // corg: Extrinsic parameter origin
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_ExtrinsicOriginSource] = kVTCameraCalibrationExtrinsicOriginSource_StereoCameraSystemBaseline
        
        // uqua: Extrinsic parameter rotation
        let defaultQuaternion = [0.0, 0.0, 0.0] // ix, iy, iz (implicit w=1)
        lensConfig[kVTCompressionPropertyCameraCalibrationKey_ExtrinsicOrientationQuaternion] = defaultQuaternion
        */
        lensCollection.append(lensConfig)
        
        return lensCollection
    }
    
    // MARK: - FOV Calculation
    private static func calculateHorizontalFOVMillidegrees(intrinsicMatrix: matrix_float3x3, imageWidth: Float) -> UInt32 {
        // FOV = 2 * atan(width / (2 * fx))
        let fx = intrinsicMatrix[0][0]  // Focal length (x direction)
        let fovRadians = 2.0 * atan(imageWidth / (2.0 * fx))
        let fovDegrees = fovRadians * 180.0 / Float.pi
        let fovMillidegrees = UInt32(fovDegrees * 1000.0)  // Convert to millidegrees (1/1000 degree)
        return fovMillidegrees
    }
    
    // MARK: - Compression Properties from Intrinsic Matrix
    static func createCompressionPropertiesFromIntrinsicMatrix(_ intrinsicMatrix: matrix_float3x3, imageSize: CGSize) -> [CFString: Any] {
        var compressionProperties: [CFString: Any] = [
            kVTCompressionPropertyKey_ProjectionKind: kVTProjectionKind_ParametricImmersive
        ]
        
        // Calculate FOV from intrinsic matrix and image size
        let horizontalFOVMillidegrees = calculateHorizontalFOVMillidegrees(
            intrinsicMatrix: intrinsicMatrix,
            imageWidth: Float(imageSize.width)
        )
        compressionProperties[kVTCompressionPropertyKey_HorizontalFieldOfView] = horizontalFOVMillidegrees
        
        let fovDegrees = Float(horizontalFOVMillidegrees) / 1000.0
        print("Calculated horizontal FOV: \(fovDegrees)° (\(horizontalFOVMillidegrees) millidegrees)")
        
        let lensCollection = createLensCollectionFromIntrinsicMatrix(intrinsicMatrix, imageSize: imageSize)
        compressionProperties[kVTCompressionPropertyKey_CameraCalibrationDataLensCollection] = lensCollection
        
        return compressionProperties
    }
}
