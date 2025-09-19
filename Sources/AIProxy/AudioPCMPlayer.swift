//
//  AudioPCMPlayer.swift
//
//
//  Created by Lou Zell on 11/27/24.
//

import Foundation
import AVFoundation
import Accelerate

/// # Warning
/// The order that you initialize `AudioPCMPlayer()` and `MicrophonePCMSampleVendor()` matters, unfortunately.
///
/// The voice processing audio unit on iOS has a volume bug that is not present on macOS.
/// The volume of playback depends on the initialization order of AVAudioEngine and the `kAudioUnitSubType_VoiceProcessingIO` Audio Unit.
/// We use AudioEngine for playback in this file, and the voice processing audio unit in MicrophonePCMSampleVendor.
///
/// I find the best result to be initializing `AudioPCMPlayer()` first. Otherwise, the playback volume is too quiet on iOS.
///
/// There are workaround here, but they don't yield good results when a user has headphones attached:
/// https://forums.developer.apple.com/forums/thread/721535
///
/// See the "Sidenote" section here for the unfortunate dependency on order:
/// https://stackoverflow.com/questions/57612695/avaudioplayer-volume-low-with-voiceprocessingio
@AIProxyActor final class AudioPCMPlayer {

    let audioEngine: AVAudioEngine
    var currentRMS: ((Float) -> Void)?
    private let inputFormat: AVAudioFormat
    private let playableFormat: AVAudioFormat
    private let playerNode: AVAudioPlayerNode

    init(audioEngine: AVAudioEngine) async throws {
        self.audioEngine = audioEngine
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioPCMPlayerError.couldNotConfigureAudioEngine(
                "Could not create input format for AudioPCMPlayerError"
            )
        }

        guard let playableFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioPCMPlayerError.couldNotConfigureAudioEngine(
                "Could not create playback format for AudioPCMPlayerError"
            )
        }

        let node = AVAudioPlayerNode()

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.outputNode, format: playableFormat)

        self.playerNode = node
        self.inputFormat = inputFormat
        self.playableFormat = playableFormat
    }

    deinit {
        logIf(.debug)?.debug("AudioPCMPlayer is being freed")
    }

    public func playPCM16Audio(from base64String: String) {
        guard let audioData = Data(base64Encoded: base64String) else {
            logIf(.error)?.error("Could not decode base64 string for audio playback")
            return
        }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: (
                AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(audioData.count),
                    mData: UnsafeMutableRawPointer(mutating: (audioData as NSData).bytes)
                )
            )
        )

        guard let inPCMBuf = AVAudioPCMBuffer(
            pcmFormat: self.inputFormat,
            bufferListNoCopy: &bufferList
        ) else {
            logIf(.error)?.error("Could not create input buffer for audio playback")
            return
        }

        guard let outPCMBuf = AVAudioPCMBuffer(
            pcmFormat: self.playableFormat,
            frameCapacity: AVAudioFrameCount(UInt32(audioData.count) * 2)
        ) else {
            logIf(.error)?.error("Could not create output buffer for audio playback")
            return
        }

        guard let converter = AVAudioConverter(from: self.inputFormat, to: self.playableFormat) else {
            logIf(.error)?.error("Could not create audio converter needed to map from pcm16int to pcm32float")
            return
        }

        do {
            try converter.convert(to: outPCMBuf, from: inPCMBuf)
        } catch {
            logIf(.error)?.error("Could not map from pcm16int to pcm32float: \(error.localizedDescription)")
            return
        }

        if self.audioEngine.isRunning {
            // #if os(macOS)
            // if AIProxyUtils.headphonesConnected {
            //    addGain(to: outPCMBuf, gain: 2.0)
            // }
            // #endif
            self.playerNode.scheduleBuffer(outPCMBuf, at: nil, options: [], completionHandler: { [weak self] in
                self?.currentRMS?(outPCMBuf.normalizedRMS)
            })
            self.playerNode.play()
        }
    }

    public func interruptPlayback() {
        logIf(.debug)?.debug("Interrupting playback")
        self.playerNode.stop()
    }
}

private func addGain(to buffer: AVAudioPCMBuffer, gain: Float) {
    guard let channelData = buffer.floatChannelData else {
        logIf(.info)?.info("Interrupting playback")
        return
    }

    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)

    for channel in 0..<channelCount {
        let samples = channelData[channel]
        for sampleIndex in 0..<frameLength {
            samples[sampleIndex] *= gain
        }
    }
}

public extension AVAudioPCMBuffer {
    
    var rms: Float {
        let frameLength = Int(frameLength)
        
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = floatChannelData?[0] else { return 0 }
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            return rms
            
        case .pcmFormatInt16:
            guard let channelData = int16ChannelData?[0] else { return 0 }
            
            var floats = [Float](repeating: 0, count: frameLength)
            vDSP_vflt16(channelData, 1, &floats, 1, vDSP_Length(frameLength))
            
            var normalized = [Float](repeating: 0, count: frameLength)
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(&floats, 1, &scale, &normalized, 1, vDSP_Length(frameLength))
            
            var rms: Float = 0
            vDSP_rmsqv(&normalized, 1, &rms, vDSP_Length(frameLength))
            return rms
            
        default:
            print("Unsupported AVAudioPCMBuffer format: ", format)
            return 0
        }
    }
    
    var rmsdB: Float {
        let minRMS: Float = 0.000_000_1
        return 20 * log10(max(rms, minRMS))
    }
    
    var normalizedRMS: Float {
        let minDb: Float = -50
        let maxDb: Float = 0
        let clamped = max(min(rmsdB, maxDb), minDb)
        let normalized = (clamped - minDb) / (maxDb - minDb)
        return max(0.08, normalized)
    }
}
