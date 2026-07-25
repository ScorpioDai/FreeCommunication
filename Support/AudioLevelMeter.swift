import Foundation

enum AudioLevelMeter {
    static func normalizedLevel(fromFloat32PCM data: Data) -> Double {
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Float.self)
            guard !samples.isEmpty else { return 0 }

            let stride = max(1, samples.count / 512)
            var sumOfSquares = 0.0
            var sampledCount = 0
            for index in Swift.stride(from: 0, to: samples.count, by: stride) {
                let sample = Double(samples[index])
                sumOfSquares += sample * sample
                sampledCount += 1
            }

            guard sampledCount > 0 else { return 0 }
            let rms = sqrt(sumOfSquares / Double(sampledCount))
            guard rms > 0.0005 else { return 0 }
            let decibels = 20 * log10(rms)
            let scaled = min(1, max(0, (decibels + 55) / 52))
            return pow(scaled, 0.72)
        }
    }
}
