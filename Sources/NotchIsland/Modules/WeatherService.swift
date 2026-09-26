import Foundation
import CoreLocation
import Combine

struct WeatherDay: Identifiable { let id = UUID(); let date: Date; let tMin: Double; let tMax: Double; let code: Int }
struct WeatherHour: Identifiable { let id = UUID(); let date: Date; let temp: Double; let code: Int; let isDay: Bool }
struct WeatherNow { let temp: Double; let feels: Double; let wind: Double; let code: Int; let isDay: Bool; let city: String; let tMin: Double; let tMax: Double }

/// Open-Meteo podle polohy Macu (CoreLocation), s náhradou podle IP adresy. Bez klíče, bez nastavení.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()
    @Published private(set) var now: WeatherNow?
    @Published private(set) var days: [WeatherDay] = []
    @Published private(set) var hours: [WeatherHour] = []
    @Published private(set) var error: String?
    private var timer: Timer?
    private let lm = CLLocationManager()
    private var coord: CLLocationCoordinate2D?
    private var cityName = ""

    private override init() {
        super.init()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        // když poloha nedorazí do 4 s, použijeme IP
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.coord == nil else { return }
            Task { await self.locateByIP(); await self.refresh() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            let moved = self.coord.map { abs($0.latitude - l.coordinate.latitude) > 0.02 || abs($0.longitude - l.coordinate.longitude) > 0.02 } ?? true
            self.coord = l.coordinate
            self.lm.stopUpdatingLocation()
            if moved { await self.reverseGeocode(l); await self.refresh() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.coord == nil { await self.locateByIP(); await self.refresh() } }
    }

    private func reverseGeocode(_ l: CLLocation) async {
        if let p = try? await CLGeocoder().reverseGeocodeLocation(l).first { cityName = p.locality ?? p.subAdministrativeArea ?? p.name ?? "" }
    }

    private func locateByIP() async {
        guard let url = URL(string: "https://ipapi.co/json/"), let (d, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let lat = j["latitude"] as? Double, let lon = j["longitude"] as? Double else { return }
        coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        cityName = j["city"] as? String ?? ""
    }

    func refresh() async {
        guard let c = coord else { return }
        do {
            var u = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            u.queryItems = [.init(name: "latitude", value: "\(c.latitude)"), .init(name: "longitude", value: "\(c.longitude)"),
                            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"),
                            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
                            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
                            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "6")]
            let (d, _) = try await URLSession.shared.data(from: u.url!)
            guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let cur = j["current"] as? [String: Any], let daily = j["daily"] as? [String: Any], let hourly = j["hourly"] as? [String: Any] else { return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let dates = daily["time"] as? [String] ?? [], mx = daily["temperature_2m_max"] as? [Double] ?? []
            let mn = daily["temperature_2m_min"] as? [Double] ?? [], codes = daily["weather_code"] as? [Int] ?? []
            days = dates.indices.compactMap { i in
                guard let dt = f.date(from: dates[i]), i < mx.count, i < mn.count, i < codes.count else { return nil }
                return WeatherDay(date: dt, tMin: mn[i], tMax: mx[i], code: codes[i])
            }
            let hf = DateFormatter(); hf.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let ht = hourly["time"] as? [String] ?? [], hT = hourly["temperature_2m"] as? [Double] ?? []
            let hc = hourly["weather_code"] as? [Int] ?? [], hd = hourly["is_day"] as? [Int] ?? []
            let nowDate = Date().addingTimeInterval(-3600)
            hours = Array(ht.indices.compactMap { i -> WeatherHour? in
                guard let dt = hf.date(from: ht[i]), dt >= nowDate, i < hT.count, i < hc.count else { return nil }
                return WeatherHour(date: dt, temp: hT[i], code: hc[i], isDay: i < hd.count ? hd[i] == 1 : true)
            }.prefix(12))
            let displayCity = UserDefaults.standard.string(forKey: "weatherCityOverride") ?? cityName
            now = WeatherNow(temp: cur["temperature_2m"] as? Double ?? 0, feels: cur["apparent_temperature"] as? Double ?? 0,
                             wind: cur["wind_speed_10m"] as? Double ?? 0, code: cur["weather_code"] as? Int ?? 0,
                             isDay: (cur["is_day"] as? Int ?? 1) == 1, city: displayCity, tMin: mn.first ?? 0, tMax: mx.first ?? 0)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"; case 45, 48: return "cloud.fog.fill"; case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"; case 71...77, 85, 86: return "cloud.snow.fill"; case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    static func text(_ code: Int) -> String {
        switch code {
        case 0: return L("Jasno"); case 1: return L("Skoro jasno"); case 2: return L("Polojasno"); case 3: return L("Zataženo")
        case 45, 48: return L("Mlha"); case 51...57: return L("Mrholení"); case 61...67: return L("Déšť"); case 71...77: return L("Sněžení")
        case 80...82: return L("Přeháňky"); case 85, 86: return L("Sněhové přeháňky"); case 95...99: return L("Bouřka"); default: return "–"
        }
    }
    /// Gradient pozadí jako v Apple Počasí.
    static func gradient(_ code: Int, isDay: Bool) -> [UInt] {
        if !isDay { return [0x1B2440, 0x0B0F1F] }
        switch code {
        case 0: return [0x3A8DE0, 0x7CC0F5]
        case 1, 2: return [0x4A93D6, 0x9CC6E8]
        case 3, 45, 48: return [0x6E7C8C, 0xA3ADB8]
        case 51...67, 80...82: return [0x4A5A6E, 0x7A8CA0]
        case 71...77, 85, 86: return [0x8FA6BD, 0xD6E1EA]
        case 95...99: return [0x2C3444, 0x55637A]
        default: return [0x4A93D6, 0x9CC6E8]
        }
    }
}
