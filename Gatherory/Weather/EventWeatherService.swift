import CoreLocation
import Foundation
import Observation
import WeatherKit

struct EventWeatherForecast: Equatable, Sendable {
    let date: Date
    let conditionDescription: String
    let symbolName: String
    let highTemperature: Measurement<UnitTemperature>
    let lowTemperature: Measurement<UnitTemperature>
    let precipitationChance: Double

    var highTemperatureText: String {
        temperatureText(highTemperature)
    }

    var lowTemperatureText: String {
        temperatureText(lowTemperature)
    }

    var precipitationChanceText: String {
        precipitationChance.formatted(.percent.precision(.fractionLength(0)))
    }

    private func temperatureText(_ temperature: Measurement<UnitTemperature>) -> String {
        let unit: UnitTemperature = Locale.current.measurementSystem == .metric ? .celsius : .fahrenheit
        let value = temperature.converted(to: unit).value
        return value.formatted(.number.precision(.fractionLength(0))) + "°"
    }
}

struct EventWeatherAttribution: Equatable, Sendable {
    let serviceName: String
    let legalPageURL: URL
    let combinedMarkLightURL: URL
    let combinedMarkDarkURL: URL
}

enum EventWeatherPhase: Equatable, Sendable {
    case idle
    case loading
    case forecast(EventWeatherForecast)
    case missingLocation
    case outsideForecastRange
    case pastEvent
    case unavailable
}

protocol EventWeatherProviding: Sendable {
    func dailyForecast(latitude: Double, longitude: Double) async throws -> [EventWeatherForecast]
    func attribution() async throws -> EventWeatherAttribution
}

struct WeatherKitEventWeatherProvider: EventWeatherProviding {
    private let service = WeatherService.shared

    func dailyForecast(latitude: Double, longitude: Double) async throws -> [EventWeatherForecast] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let forecast = try await service.weather(for: location, including: .daily)

        return forecast.map { day in
            EventWeatherForecast(
                date: day.date,
                conditionDescription: day.condition.description,
                symbolName: day.symbolName,
                highTemperature: day.highTemperature,
                lowTemperature: day.lowTemperature,
                precipitationChance: day.precipitationChance
            )
        }
    }

    func attribution() async throws -> EventWeatherAttribution {
        let attribution = try await service.attribution
        return EventWeatherAttribution(
            serviceName: attribution.serviceName,
            legalPageURL: attribution.legalPageURL,
            combinedMarkLightURL: attribution.combinedMarkLightURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL
        )
    }
}

@Observable
@MainActor
final class EventWeatherModel {
    private(set) var phase: EventWeatherPhase = .idle
    private(set) var attribution: EventWeatherAttribution?

    private let provider: any EventWeatherProviding
    private var requestID = UUID()

    init() {
        provider = WeatherKitEventWeatherProvider()
    }

    init(provider: any EventWeatherProviding) {
        self.provider = provider
    }

    func load(for item: TimelineItem, calendar: Calendar = .autoupdatingCurrent) async {
        await load(
            on: item.scheduledAt,
            location: item.eventLocation,
            calendar: calendar
        )
    }

    func load(
        on eventDate: Date,
        location: EventLocation?,
        calendar: Calendar = .autoupdatingCurrent
    ) async {
        let currentRequestID = UUID()
        requestID = currentRequestID
        attribution = nil

        guard eventDate >= calendar.startOfDay(for: .now) else {
            phase = .pastEvent
            return
        }

        guard let latitude = location?.latitude,
              let longitude = location?.longitude else {
            phase = .missingLocation
            return
        }

        phase = .loading

        do {
            async let forecastRequest = provider.dailyForecast(
                latitude: latitude,
                longitude: longitude
            )
            async let attributionRequest = provider.attribution()

            let (forecast, loadedAttribution) = try await (forecastRequest, attributionRequest)
            guard requestID == currentRequestID else { return }

            attribution = loadedAttribution
            if let day = Self.forecast(on: eventDate, from: forecast, calendar: calendar) {
                phase = .forecast(day)
            } else {
                phase = .outsideForecastRange
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestID == currentRequestID else { return }
            phase = .unavailable
        }
    }

    nonisolated static func forecast(
        on date: Date,
        from forecast: [EventWeatherForecast],
        calendar: Calendar
    ) -> EventWeatherForecast? {
        forecast.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
