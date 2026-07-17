import AppKit
import Foundation

/// Short 8-bit style blips (playful arcade energy — original tones, not licensed music).
enum BezelSound {
    enum Kind: Sendable {
        case attention
        case allow
        case deny
        case sessionUp
        case done
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "bezel.sounds.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "bezel.sounds.enabled") }
    }

    /// Retained while playing; guarded by `playLock`. Marked unsafe for Swift 6 global mutability.
    private static let playLock = NSLock()
    nonisolated(unsafe) private static var active: [NSSound] = []

    static func play(_ kind: Kind) {
        guard isEnabled else { return }
        let notes: [(freq: Double, ms: Int)]
        switch kind {
        case .attention:
            notes = [(523.25, 55), (659.25, 55), (783.99, 95)]
        case .allow:
            notes = [(987.77, 45), (1318.51, 100)]
        case .deny:
            notes = [(196.0, 70), (146.83, 110)]
        case .sessionUp:
            notes = [(392.0, 40), (523.25, 70)]
        case .done:
            notes = [(659.25, 45), (523.25, 45), (392.0, 75)]
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for (i, n) in notes.enumerated() {
                guard let url = renderWav(frequency: n.freq, durationMs: n.ms) else { continue }
                guard let sound = NSSound(contentsOf: url, byReference: false) else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                DispatchQueue.main.async {
                    playLock.lock()
                    active.append(sound)
                    playLock.unlock()
                    sound.play()
                }
                Thread.sleep(forTimeInterval: Double(n.ms) / 1000.0 + 0.05)
                try? FileManager.default.removeItem(at: url)
                if i + 1 < notes.count {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            DispatchQueue.main.async {
                playLock.lock()
                active.removeAll { !$0.isPlaying }
                playLock.unlock()
            }
        }

        DispatchQueue.main.async {
            BezelHaptics.alignment()
        }
    }

    private static func renderWav(frequency: Double, durationMs: Int) -> URL? {
        let sampleRate = 22_050.0
        let count = max(32, Int(sampleRate * Double(durationMs) / 1000.0))
        var pcm = [Int16](repeating: 0, count: count)
        let twoPi = 2.0 * Double.pi
        let attack = min(48, count / 4)
        let release = min(96, count / 3)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let phase = sin(twoPi * frequency * t)
            let square: Double = phase >= 0 ? 0.2 : -0.2
            let env: Double
            if i < attack {
                env = Double(i) / Double(attack)
            } else if i > count - release {
                env = Double(count - i) / Double(release)
            } else {
                env = 1
            }
            pcm[i] = Int16((square * env * Double(Int16.max)).rounded())
        }

        let dataSize = pcm.count * 2
        var out = Data()
        out.reserveCapacity(44 + dataSize)
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataSize))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2))
        appendU16(2)
        appendU16(16)
        out.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataSize))
        for s in pcm {
            var le = s.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-\(UUID().uuidString).wav")
        do {
            try out.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
