import AVFoundation
import CoreAudio
import Combine

class AudioRecorder: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private(set) var isRecording = false

    /// Publishes audio levels (0.0 to 1.0) at ~30fps while recording
    let levelPublisher = PassthroughSubject<Float, Never>()

    func start() {
        // Force built-in mic even if Bluetooth audio is connected
        selectBuiltInMic()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmur_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true

            // Sample audio levels for waveform
            meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                // Convert dB (-160...0) to 0...1
                let level = max(0, min(1, (db + 50) / 50))
                self.levelPublisher.send(level)
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func selectBuiltInMic() {
        // Find built-in mic via CoreAudio and set it as default input
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &devices) == noErr else { return }

        for device in devices {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var bufferSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &inputAddress, 0, nil, &bufferSize) == noErr, bufferSize > 0 else { continue }

            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferList.deallocate() }
            guard AudioObjectGetPropertyData(device, &inputAddress, 0, nil, &bufferSize, bufferList) == noErr else { continue }

            let channelCount = bufferList.pointee.mBuffers.mNumberChannels
            guard channelCount > 0 else { continue }

            // Check transport type — built-in has kAudioDeviceTransportTypeBuiltIn
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transportType) == noErr else { continue }

            if transportType == kAudioDeviceTransportTypeBuiltIn {
                // Set as default input device
                var defaultAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var deviceID = device
                AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
                break
            }
        }
    }

    func stop(completion: @escaping (URL?) -> Void) {
        meterTimer?.invalidate()
        meterTimer = nil

        guard let recorder = audioRecorder, isRecording else {
            completion(nil)
            return
        }

        let url = recorder.url
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        completion(url)
    }
}
