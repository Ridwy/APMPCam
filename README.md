# APMPCam - Wide FOV Video Recording with APMP Metadata

An iOS/iPadOS camera application that demonstrates recording ultra-wide angle video with embedded Wide FOV APMP (Apple Projected Media Profile) metadata using Video Toolbox APIs.

While iPhone's ultra-wide camera captures approximately 105° field of view (not quite reaching 120°), it provides valuable samples for APMP specification research and development. Recorded videos are automatically saved to the Camera Roll and can be transferred to Vision Pro via AirDrop for projected playback.

## Requirements

- Xcode 26.0+
- iOS/iPadOS 26.0+
- Device with ultra-wide camera

## Installation

1. Generate the Xcode project:
```bash
xcodegen
```

2. Open the project:
```bash
open APMPCam.xcodeproj
```

3. Configure your Developer Team in Xcode project settings

4. Build and run on a physical device (camera not available in simulator)

## Technical Details

### APMP Wide FOV Metadata

The app extracts camera intrinsic parameters from the CMSampleBuffer and embeds them as Video Toolbox compression properties:

- **Intrinsic Matrix (K-matrix)**: Contains focal length (fx, fy) and principal point (cx, cy)
- **Horizontal FOV**: Calculated from intrinsic matrix and image dimensions

Since geometric distortion correction is enabled, other lens parameters remain at their default values.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

This app was created for research supporting @Ridwy's talk at iOSDC Japan 2025 and made public in response to requests from attendees. Many thanks to this wonderful conference.

[Presentation Slide](https://speakerdeck.com/ridwy/kong-jian-zai-xian-li-nojian-apmpwodu-mijie-ku)

## Note

This is a proof-of-concept implementation focused on demonstrating APMP vexu box embedding. Audio recording is not included to keep the code simple and focused. Production use may require additional error handling and feature enhancements.