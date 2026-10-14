import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Gatherory

@MainActor
struct UploadImagePreparationTests {
    @Test("R2 prepare and PUT use the same downsampled file, MIME type, and byte count")
    func uploadContract() async throws {
        let source = temporaryURL("png")
        // Deliberately stale queue metadata must not describe the prepared JPEG.
        let original = try photo(size: CGSize(width: 3200, height: 1600))
        try original.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreparedImageUploadProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transfer = PendingMediaTransferSnapshot(id: UUID(), scopeID: UUID(), entityID: UUID(),
            localFileURL: source, contentType: "image/png", attemptCount: 3)
        let transport = R2MediaTransport(baseURL: URL(string: "https://upload-preparation.invalid")!,
            urlSession: session, tokenStore: UploadTestTokens())
        #expect(try await transport.upload(transfer) == transfer.id)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test("Upload photos are bounded, correctly oriented, and leave originals untouched")
    func boundedPhoto() async throws {
        let original = try photo(size: CGSize(width: 3200, height: 1600))
        let source = temporaryURL("jpg")
        try original.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let result = try await Task.detached { try UploadImagePreparation.prepare(sourceURL: source) }.value
        defer { result.removeTemporaryFile() }
        #expect(result.contentType == "image/jpeg")
        #expect(result.byteSize <= UploadImagePreparation.targetByteSize)
        #expect(try Data(contentsOf: result.fileURL).count == result.byteSize)
        #expect(try Data(contentsOf: source) == original)
        let properties = try properties(result.fileURL)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2560)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1280)
        result.removeTemporaryFile()
        #expect(!FileManager.default.fileExists(atPath: result.fileURL.path))
    }

    @Test("An existing queued image over 20 MB can be prepared without reselecting it")
    func oversizedImage() async throws {
        // A valid, uncompressed TIFF exercises the file-size limit without fake padding.
        let image = try #require(UIImage(data: photo(size: CGSize(width: 3000, height: 2500)))?.cgImage)
        let source = temporaryURL("tiff")
        defer { try? FileManager.default.removeItem(at: source) }
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let originalSize = try #require(source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(originalSize > 20 * 1024 * 1024)
        let result = try await Task.detached { try UploadImagePreparation.prepare(sourceURL: source) }.value
        defer { result.removeTemporaryFile() }
        #expect(result.byteSize <= UploadImagePreparation.targetByteSize)
        #expect(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize == originalSize)
    }

    @Test("Transparent artwork stays transparent and small images are not upscaled")
    func transparentArtwork() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let data = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 20, y: 20, width: 40, height: 40))
        }
        let source = temporaryURL("png")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let result = try UploadImagePreparation.prepare(sourceURL: source)
        defer { result.removeTemporaryFile() }
        #expect(result.contentType == "image/png")
        let properties = try properties(result.fileURL)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 120)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 80)
    }

    @Test("EXIF orientation is baked into upload pixels")
    func orientation() throws {
        let image = try #require(UIImage(data: photo(size: CGSize(width: 120, height: 80)))?.cgImage)
        let source = temporaryURL("jpg")
        defer { try? FileManager.default.removeItem(at: source) }
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let result = try UploadImagePreparation.prepare(sourceURL: source)
        defer { result.removeTemporaryFile() }
        let properties = try properties(result.fileURL)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 80)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 120)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test("Invalid queued images fail without changing the original")
    func invalidImage() throws {
        let source = temporaryURL("jpg")
        let original = Data("not an image".utf8)
        try original.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        do {
            let result = try UploadImagePreparation.prepare(sourceURL: source)
            result.removeTemporaryFile()
            Issue.record("Invalid image unexpectedly prepared")
        } catch MediaSyncFailure.invalidImage {}
        #expect(try Data(contentsOf: source) == original)
    }

    @Test("Upload preparation respects cancellation")
    func cancellation() async throws {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try UploadImagePreparation.prepare(sourceURL: URL(fileURLWithPath: "/does-not-exist"))
        }
        do {
            let result = try await task.value
            result.removeTemporaryFile()
            Issue.record("Cancelled preparation unexpectedly succeeded")
        } catch is CancellationError {}
    }

    private func photo(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 1) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
}

@MainActor
private final class UploadTestTokens: SessionTokenStore {
    func read() -> String? { "test-token" }
    func save(_ token: String) {}
    func delete() {}
}

private final class PreparedImageUploadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let payload: [String: Any]
            if request.url!.lastPathComponent == "upload" {
                guard request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg",
                      let filename = request.value(forHTTPHeaderField: "X-Test-Filename"),
                      let expectedSize = request.value(forHTTPHeaderField: "X-Test-Byte-Size").flatMap(Int.init)
                else { throw URLError(.badServerResponse) }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                let expected = try Data(contentsOf: file)
                guard expected.count == expectedSize else { throw URLError(.badServerResponse) }
                let uploaded = try bodyData()
                guard uploaded == expected else { throw URLError(.badServerResponse) }
                payload = [:]
            } else {
                guard let body = try JSONSerialization.jsonObject(with: bodyData()) as? [String: Any],
                      let id = body["mediaAssetId"] as? String else { throw URLError(.badServerResponse) }
                if request.url!.lastPathComponent == "prepare" {
                    guard let filename = body["originalFilename"] as? String,
                          filename.hasSuffix(".jpg"), body["contentType"] as? String == "image/jpeg",
                          let size = body["byteSize"] as? Int, size <= 5 * 1024 * 1024
                    else { throw URLError(.badServerResponse) }
                    let data = try Data(contentsOf: FileManager.default.temporaryDirectory.appendingPathComponent(filename))
                    guard data.count == size, data.starts(with: [0xff, 0xd8]) else { throw URLError(.badServerResponse) }
                    payload = ["ok": true, "data": ["mediaAssetId": id, "method": "PUT",
                        "uploadUrl": "https://upload-preparation.invalid/upload",
                        "requiredHeaders": ["Content-Type": "image/jpeg", "X-Test-Filename": filename,
                                            "X-Test-Byte-Size": String(size)]]]
                } else {
                    payload = ["ok": true, "data": ["mediaAssetId": id, "url": "https://upload-preparation.invalid/image"]]
                }
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    private func bodyData() throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
