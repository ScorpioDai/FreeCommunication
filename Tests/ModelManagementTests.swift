import Foundation
import XCTest
@testable import FreeCommunication

final class ModelManagementTests: XCTestCase {
    func testFixedModelDirectoriesUseTheCurrentUsersDocumentsFolder() {
        let expectedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AI Models", isDirectory: true)

        XCTAssertEqual(Defaults.modelsDirectory, expectedRoot)
        XCTAssertEqual(
            ManagedModel.asr.directoryURL.lastPathComponent,
            "animaslabs:nemotron-speech-streaming-en-0.6b-mlx-8bit"
        )
        XCTAssertEqual(
            ManagedModel.nmt.directoryURL.lastPathComponent,
            "Helsinki-NLP:opus-mt-en-zh"
        )
    }

    func testHuggingFaceManifestDecodesRegularAndLFSFileSizes() throws {
        let data = Data(
            """
            {
              "id": "example/model",
              "sha": "0123456789abcdef",
              "siblings": [
                {"rfilename": "config.json", "size": 1403},
                {"rfilename": "model.bin", "lfs": {"size": 312087009}}
              ]
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(HuggingFaceModelManifest.self, from: data)

        XCTAssertEqual(manifest.id, "example/model")
        XCTAssertEqual(manifest.siblings[0].byteCount, 1403)
        XCTAssertEqual(manifest.siblings[1].byteCount, 312_087_009)
    }

    func testTranslationPolicyKeepsDisabledSegmentsSourceOnlyAfterReenabling() {
        var policy = LiveTranslationPolicy()

        XCTAssertTrue(policy.allowsTranslation(for: 5))
        policy.setEnabled(false, at: 10)
        XCTAssertTrue(policy.allowsTranslation(for: 9.9))
        XCTAssertFalse(policy.allowsTranslation(for: 10))
        XCTAssertFalse(policy.allowsTranslation(for: 18))

        policy.setEnabled(true, at: 20)
        XCTAssertFalse(policy.allowsTranslation(for: 15))
        XCTAssertTrue(policy.allowsTranslation(for: 20))
        XCTAssertTrue(policy.allowsTranslation(for: 28))

        policy.reset()
        XCTAssertTrue(policy.allowsTranslation(for: 15))
    }

    func testDownloadProgressIsClampedToAValidFraction() {
        XCTAssertEqual(ModelDownloadProgress(
            completedBytes: 50,
            totalBytes: 100,
            currentFile: ""
        ).fractionCompleted, 0.5)
        XCTAssertEqual(ModelDownloadProgress(
            completedBytes: 120,
            totalBytes: 100,
            currentFile: ""
        ).fractionCompleted, 1)
        XCTAssertEqual(ModelDownloadProgress(
            completedBytes: 10,
            totalBytes: 0,
            currentFile: ""
        ).fractionCompleted, 0)
    }
}
