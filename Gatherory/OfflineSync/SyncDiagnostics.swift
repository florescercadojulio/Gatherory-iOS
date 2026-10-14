import Foundation
import OSLog
import PostHog
import CryptoKit

/// Deliberately excludes URLs, bodies, tokens, filenames and user content.
enum SyncDiagnostics {
    nonisolated static func accountKey(_ userID: String?) -> String {
        guard let userID else { return "signed_out" }
        return SHA256.hash(data: Data(userID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func record(_ event: String, fields: [String: String] = [:], error: Error? = nil) {
        var fields = fields
        if let error {
            let nsError = error as NSError
            fields["error_type"] = String(describing: type(of: error))
            fields["error_domain"] = nsError.domain
            fields["error_number"] = String(nsError.code)
            if let failure = error as? CloudSyncFailure {
                switch failure {
                case .server(let code): fields["failure_code"] = code
                case .invalidSession: fields["failure_code"] = "INVALID_SESSION"
                case .invalidResponse: fields["failure_code"] = "INVALID_RESPONSE"
                case .payloadTooLarge: fields["failure_code"] = "PAYLOAD_TOO_LARGE"
                }
            }
        }
        let line = fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: " ")
        let logger = Logger(subsystem: "com.guide-systems.gatherory", category: "Sync")
        if error != nil {
            logger.error("\(event, privacy: .public) \(line, privacy: .public)")
            PostHogSDK.shared.logger?.error(event, attributes: fields)
        } else {
            logger.info("\(event, privacy: .public) \(line, privacy: .public)")
            PostHogSDK.shared.logger?.info(event, attributes: fields)
        }
    }

    nonisolated static func serverFailure(in data: Data) -> (code: String?, errorID: String?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        let envelope = root["error"] as? [String: Any] ?? root
        // Support both the legacy sync envelope and the typed media envelope.
        let code = root["error"] as? String ?? envelope["code"] as? String
        return (code, envelope["errorId"] as? String)
    }

    nonisolated static func decodePath(_ error: Error) -> String {
        let path: [any CodingKey]
        switch error {
        case DecodingError.keyNotFound(let key, let context): path = context.codingPath + [key]
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context): path = context.codingPath
        default: return "unknown"
        }
        return path.map(\.stringValue).joined(separator: ".")
    }
}
