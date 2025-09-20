import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            CameraPreview(viewModel: viewModel)
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        ZStack {
                            if viewModel.isRecording {
                                // Square when recording
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: 24, height: 24)
                                    .cornerRadius(5)
                            } else {
                                // Circle when not recording
                                Circle()
                                    .fill(.red)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .overlay(
                            // White border ring
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 52, height: 52)
                        )
                    }
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                }
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
        .statusBarHidden(true)
    }
}
