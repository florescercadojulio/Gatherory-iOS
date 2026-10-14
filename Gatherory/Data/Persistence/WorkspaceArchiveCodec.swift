import Foundation

/// The JSON configuration shared by durable archives and sync entity payloads.
/// Dates retain Foundation's default deferred-to-Date representation, measured
/// from the reference date. Sorted keys keep payload comparison deterministic.
struct WorkspaceArchiveCodec {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
    }

    func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try encoder.encode(value)
    }

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder.decode(type, from: data)
    }
}
