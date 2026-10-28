import Foundation

/// Adds bounded sync failure context without forwarding server messages or request data.
enum SyncFailureLogAttributes {
    static func make(
        trigger: SyncTrigger,
        stage: String,
        error: Error,
        buildNumber: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    ) -> [String: String] {
        var attributes = [
            "trigger": trigger.rawValue,
            "stage": stage,
            "error_type": String(describing: type(of: error)),
            "build_number": safeBuildNumber(buildNumber)
        ]

        if let failure = error as? CloudSyncFailure {
            let category: String
            let serverCode: String?
            switch failure {
            case .invalidSession:
                category = "invalid_session"
                serverCode = nil
            case .invalidResponse:
                category = "invalid_response"
                serverCode = nil
            case .forbidden(let code):
                category = "forbidden"
                serverCode = code
            case .server(let code):
                category = "server"
                serverCode = code
            case .payloadTooLarge:
                category = "payload_too_large"
                serverCode = nil
            case .clientUpgradeRequired(let code):
                category = "upgrade_required"
                serverCode = code
            }
            attributes["failure_category"] = category
            if let status = httpStatus(from: serverCode) {
                attributes["http_status"] = String(status)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            attributes["url_error_code"] = String(nsError.code)
        }
        return attributes
    }

    private static func safeBuildNumber(_ value: String?) -> String {
        guard let value,
              !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else {
            return "unknown"
        }
        return value
    }

    private static func httpStatus(from code: String?) -> Int? {
        guard let code, code.hasPrefix("HTTP_") else { return nil }
        let digits = code.dropFirst("HTTP_".count)
        guard digits.utf8.count == 3,
              digits.utf8.allSatisfy({ (48...57).contains($0) }),
              let status = Int(digits),
              (100...599).contains(status) else {
            return nil
        }
        return status
    }
}
