import AVFoundation
import os

/// Plays the bridge's stereo int16 samples (already resampled to `GBP_AUDIO_RATE`, 48 kHz) through
/// AVAudioEngine, whose mixer converts to the device rate. The emulation thread paces itself on `bufferedFrames`.
final class AudioOutput {
    let sampleRate: Double
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let ring: Ring
    private(set) var isRunning = false

    /// Frames kept queued: about three video frames.
    var targetFrames: Int { Int(sampleRate / 60.0 * 3.0) }

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        ring = Ring(capacity: Int(sampleRate / 4))
    }

    func start() {
        guard !isRunning,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)
        else { return }
        let ring = self.ring
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            ring.read(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
        do {
            try engine.start()
            isRunning = true
        } catch {
            NSLog("Audio output did not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    /// 0 ... 1
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var bufferedFrames: Int { ring.count }

    func push(_ samples: UnsafePointer<Int16>, frames: Int) {
        ring.write(samples, frames: frames)
    }

    func clear() {
        ring.clear()
    }

    /// Single-producer, single-consumer ring of interleaved stereo int16, guarded by an unfair lock
    /// (held only for a copy, so the render thread never waits long).
    final class Ring: @unchecked Sendable {
        private var data: [Int16]
        private let capacity: Int
        private var readIndex = 0
        private var writeIndex = 0
        private var stored = 0
        private let lock = OSAllocatedUnfairLock()

        init(capacity: Int) {
            self.capacity = max(capacity, 1024)
            data = [Int16](repeating: 0, count: self.capacity * 2)
        }

        var count: Int { lock.withLockUnchecked { stored } }

        func clear() {
            lock.withLockUnchecked {
                readIndex = 0
                writeIndex = 0
                stored = 0
            }
        }

        func write(_ samples: UnsafePointer<Int16>, frames: Int) {
            lock.withLockUnchecked {
                for i in 0..<frames {
                    if stored == capacity {
                        // Overflow: drop the oldest frame.
                        readIndex = (readIndex + 1) % capacity
                        stored -= 1
                    }
                    data[writeIndex * 2] = samples[i * 2]
                    data[writeIndex * 2 + 1] = samples[i * 2 + 1]
                    writeIndex = (writeIndex + 1) % capacity
                    stored += 1
                }
            }
        }

        func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
            lock.withLockUnchecked {
                let available = min(frames, stored)
                for i in 0..<available {
                    left[i] = Float(data[readIndex * 2]) / 32768.0
                    right[i] = Float(data[readIndex * 2 + 1]) / 32768.0
                    readIndex = (readIndex + 1) % capacity
                }
                stored -= available
                // Underrun: silence for the rest.
                for i in available..<frames {
                    left[i] = 0
                    right[i] = 0
                }
            }
        }
    }
}
