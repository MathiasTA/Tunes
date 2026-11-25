import CoreLocation
import Foundation
import Observation

enum WeatherKind: String, Codable {
    case clear, clouds, rain, snow, thunder, fog

    var label: String {
        switch self {
        case .clear: "Clear"
        case .clouds: "Cloudy"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunder: "Thunder"
        case .fog: "Fog"
        }
    }

    /// Open-Meteo uses the WMO weather codes.
    static func from(code: Int) -> WeatherKind {
        switch code {
        case 0, 1: .clear
        case 45, 48: .fog
        case 51...67, 80...82: .rain
        case 71...77, 85, 86: .snow
        case 95...99: .thunder
        default: .clouds
        }
    }
}

struct WeatherNow: Codable, Equatable {
    var kind: WeatherKind
    var isDay: Bool
    var temperature: Double
    var place: String?
    var fetched: Date
}

/// Keeps the current weather for the Weather theme, from Open-Meteo (free, no account or key).
/// Only runs while the Weather theme is chosen; checks about every 30 minutes and keeps the last result offline.
@MainActor @Observable
final class WeatherWatcher: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherWatcher()

    private(set) var now: WeatherNow? = Store.load(WeatherNow.self, "weather.json")
    /// Why there's no weather, if something's missing (shown in Appearance).
    private(set) var problem: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        let prefs = AppModel.shared.prefs.data
        guard prefs.theme == .weather, !prefs.offline, !busy else { return }
        if !force, let n = now, Date.now.timeIntervalSince(n.fetched) < 25 * 60 { return }
        busy = true
        defer { busy = false }
        let city = prefs.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefs.weatherUseLocation, let loc = await currentLocation() {
            let place = try? await CLGeocoder().reverseGeocodeLocation(loc).first?.locality
            await fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, place: place)
        } else if !city.isEmpty {
            guard let g = await geocode(city) else { problem = "Couldn't find “\(city)”."; return }
            await fetch(lat: g.lat, lon: g.lon, place: g.name)
        } else {
            problem = prefs.weatherUseLocation
                ? "Allow location for Tunes in iPhone Settings, or type a city below."
                : "Type a city to get its weather."
        }
    }

    // MARK: Location

    private func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: manager.requestLocation()
        }
        return await withCheckedContinuation { c in
            waiting.append(c)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        let w = waiting
        waiting = []
        for c in w { c.resume(returning: loc) }
    }

    private func authChanged() {
        guard !waiting.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: return
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.finish(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authChanged() }
    }

    // MARK: Open-Meteo

    private func geocode(_ city: String) async -> (lat: Double, lon: Double, name: String)? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        guard let url = c.url,
              let res = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let lat = (first["latitude"] as? NSNumber)?.doubleValue,
              let lon = (first["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return (lat, lon, first["name"] as? String ?? city)
    }

    private func fetch(lat: Double, lon: Double, place: String?) async {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
                        URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
                        URLQueryItem(name: "current", value: "weather_code,is_day,temperature_2m")]
        guard let url = c.url,
              let res = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let cur = json["current"] as? [String: Any] else {
            problem = "Couldn't get the weather right now."
            return
        }
        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? 3
        let day = ((cur["is_day"] as? NSNumber)?.intValue ?? 1) == 1
        let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue ?? 0
        let w = WeatherNow(kind: .from(code: code), isDay: day, temperature: temp, place: place, fetched: .now)
        now = w
        problem = nil
        Store.save(w, "weather.json")
    }
}
