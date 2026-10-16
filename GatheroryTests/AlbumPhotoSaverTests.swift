import Foundation
import Photos
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct AlbumPhotoSaverTests {
    @Test("Opening an album and an empty save never ask for photo access")
    func noPermissionUntilExplicitNonemptySave() async {
        let calls = SaveCalls()
        let saver = makeSaver(calls: calls, status: .notDetermined)
        #expect(calls.statusChecks.isEmpty)
        #expect(calls.permissionRequests.isEmpty)
        #expect(!saver.isSaving)
        #expect(await saver.save([]) == .saved(0))
        #expect(calls.statusChecks.isEmpty)
        #expect(calls.permissionRequests.isEmpty)
        #expect(calls.batches.isEmpty)
    }

    @Test("A granted add-only request saves original image bytes in one ordered batch")
    func requestsAddOnlyAndPreservesOriginals() async {
        let calls = SaveCalls()
        let saver = makeSaver(calls: calls, status: .notDetermined, requestedStatus: .authorized)
        let first = moment(.red)
        let second = moment(.blue)

        #expect(await saver.save([second, first]) == .saved(2))
        #expect(calls.statusChecks == [.addOnly])
        #expect(calls.permissionRequests == [.addOnly])
        #expect(calls.batches == [[second.imageData, first.imageData]])
        #expect(!saver.isSaving)
    }

    @Test("Existing authorization avoids another permission request and deduplicates moment IDs")
    func alreadyAuthorized() async {
        let calls = SaveCalls()
        let saver = makeSaver(calls: calls, status: .authorized)
        let photo = moment(.green)

        #expect(await saver.save([photo, photo]) == .saved(1))
        #expect(calls.statusChecks == [.addOnly])
        #expect(calls.permissionRequests.isEmpty)
        #expect(calls.batches == [[photo.imageData]])
    }

    @Test("Denied and restricted access never attempt a write", arguments: [PHAuthorizationStatus.denied, .restricted])
    func deniedAccess(status: PHAuthorizationStatus) async {
        let calls = SaveCalls()
        let saver = makeSaver(calls: calls, status: status)

        #expect(await saver.save([moment(.red)]) == .permissionDenied)
        #expect(calls.permissionRequests.isEmpty)
        #expect(calls.batches.isEmpty)
        #expect(!saver.isSaving)
    }

    @Test("Declining the system permission request never writes a photo")
    func declinedPermissionRequest() async {
        let calls = SaveCalls()
        let saver = makeSaver(calls: calls, status: .notDetermined, requestedStatus: .denied)

        #expect(await saver.save([moment(.red)]) == .permissionDenied)
        #expect(calls.permissionRequests == [.addOnly])
        #expect(calls.batches.isEmpty)
        #expect(!saver.isSaving)
    }

    @Test("Any invalid image rejects the entire batch before permission or writes")
    func invalidBatchIsRejected() async {
        let photo = moment(.red)
        for invalidData in [Data(), Data([1, 2, 3]), Data(photo.imageData.prefix(20))] {
            let calls = SaveCalls()
            let saver = makeSaver(calls: calls, status: .notDetermined)
            let invalid = EventMoment(imageData: invalidData, addedBy: "Guest")

            #expect(await saver.save([photo, invalid]) == .invalidImage)
            #expect(calls.statusChecks.isEmpty)
            #expect(calls.permissionRequests.isEmpty)
            #expect(calls.batches.isEmpty)
            #expect(!saver.isSaving)
        }
    }

    @Test("A write error clears progress without automatic retry")
    func failedWriteCanBeExplicitlyRetried() async {
        let calls = SaveCalls()
        calls.failWrite = true
        let saver = makeSaver(calls: calls, status: .authorized)
        let photos = [moment(.red), moment(.blue)]

        #expect(await saver.save(photos) == .failed)
        #expect(calls.batches.count == 1)
        #expect(!saver.isSaving)

        calls.failWrite = false
        #expect(await saver.save(photos) == .saved(2))
        #expect(calls.batches.count == 2)
        #expect(calls.batches[0] == calls.batches[1])
    }

    @Test("A repeated tap while saving cannot submit a second photo transaction")
    func concurrentSaveIsRejected() async {
        let calls = SaveCalls()
        let (enteredWrite, enteredWriteContinuation) = AsyncStream<Void>.makeStream()
        var finishWrite: CheckedContinuation<Void, Never>?
        let saver = AlbumPhotoSaver(
            authorizationStatus: { _ in .authorized },
            requestAuthorization: { _ in .denied },
            writeImages: { images in
                calls.batches.append(images)
                await withCheckedContinuation { continuation in
                    finishWrite = continuation
                    enteredWriteContinuation.yield(())
                }
            }
        )
        let photo = moment(.red)
        let pendingSave = Task { await saver.save([photo]) }
        for await _ in enteredWrite { break }

        #expect(saver.isSaving)
        #expect(await saver.save([photo]) == .failed)
        #expect(calls.batches.count == 1)
        finishWrite?.resume()
        #expect(await pendingSave.value == .saved(1))
        #expect(!saver.isSaving)
        enteredWriteContinuation.finish()
    }

    @Test("The app declares localized add-only access without full photo-library permission")
    func permissionConfigurationIsAddOnly() throws {
        let purpose = try #require(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String)
        #expect(!purpose.isEmpty)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") == nil)
        let spanishURL = try #require(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "es"))
        let strings = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: spanishURL), format: nil) as? [String: String])
        #expect(strings["NSPhotoLibraryAddUsageDescription"] == "Guarda las fotos del álbum compartido que elijas en tu fototeca.")
    }

    private func moment(_ color: UIColor) -> EventMoment {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3))
        let data = renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
        return EventMoment(imageData: data, addedBy: "Guest")
    }

    private func makeSaver(
        calls: SaveCalls,
        status: PHAuthorizationStatus,
        requestedStatus: PHAuthorizationStatus = .authorized
    ) -> AlbumPhotoSaver {
        AlbumPhotoSaver(
            authorizationStatus: { level in
                calls.statusChecks.append(level)
                return status
            },
            requestAuthorization: { level in
                calls.permissionRequests.append(level)
                return requestedStatus
            },
            writeImages: { images in
                calls.batches.append(images)
                if calls.failWrite { throw SaveFailure.test }
            }
        )
    }

    private final class SaveCalls {
        var statusChecks: [PHAccessLevel] = []
        var permissionRequests: [PHAccessLevel] = []
        var batches: [[Data]] = []
        var failWrite = false
    }

    private enum SaveFailure: Error {
        case test
    }
}
