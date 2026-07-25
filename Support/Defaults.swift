import Foundation

enum Defaults {
    static let subtitleOpacityKey = "subtitleOpacity"
    static let subtitleFontSizeKey = "subtitleFontSize"
    static let liveChunkSecondsKey = "liveChunkSeconds"
    static let callVoiceProcessingKey = "callVoiceProcessingEnabled"
    private static let liveChunkMigrationKey = "liveChunkSecondsMigratedToV11"

    static let systemPythonPath = "/usr/bin/python3"

    static var modelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AI Models", isDirectory: true)
    }

    static var asrModelDirectory: URL {
        modelsDirectory.appendingPathComponent(
            "animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit",
            isDirectory: true
        )
    }

    static var nmtModelDirectory: URL {
        modelsDirectory.appendingPathComponent(
            "Helsinki-NLP:opus-mt-en-zh",
            isDirectory: true
        )
    }

    static var defaultASRPath: String {
        asrModelDirectory.path
    }

    static var defaultNMTPath: String {
        nmtModelDirectory.path
    }

    static var defaultPythonPath: String {
        bundledPythonPath ?? systemPythonPath
    }

    static var bundledPythonPath: String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL
            .appendingPathComponent("Backend", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    static var recordingsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FreeCommunication", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FreeCommunication", isDirectory: true)
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            subtitleOpacityKey: 0.74,
            subtitleFontSizeKey: 24.0,
            liveChunkSecondsKey: 3.0,
            callVoiceProcessingKey: false
        ])

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: liveChunkMigrationKey) {
            let storedValue = defaults.object(forKey: liveChunkSecondsKey) as? Double
            if storedValue == nil || storedValue == 6.0 {
                defaults.set(3.0, forKey: liveChunkSecondsKey)
            }
            defaults.set(true, forKey: liveChunkMigrationKey)
        }
    }

}
