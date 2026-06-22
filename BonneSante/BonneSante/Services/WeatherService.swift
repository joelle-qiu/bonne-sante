import CoreLocation
import Foundation

/// 一周天气预报（Open-Meteo，免费无需 Key）
/// @author jiali.qiu
struct WeatherDayForecast: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let weekday: Int
    let weekdayLabel: String
    let eveningTempC: Double?
    /// 19:00 附近降水概率 0–100
    let eveningPrecipPercent: Int?
    let weatherCode: Int
    let weatherLabel: String
    let isGoodForEveningActivity: Bool

    var eveningSummary: String {
        var parts: [String] = []
        if let temp = eveningTempC {
            parts.append("\(Int(temp.rounded()))°C")
        }
        parts.append(weatherLabel)
        if let precip = eveningPrecipPercent {
            parts.append("降水\(precip)%")
        }
        return parts.joined(separator: " · ")
    }

    /// 19:00 是否视为「下雨」→ 心情模式推荐游泳
    var isRainyAtEvening: Bool {
        if let precip = eveningPrecipPercent, precip >= 50 { return true }
        return Self.rainWeatherCodes.contains(weatherCode)
    }

    /// 雷暴类天气（游泳日需提示室内泳池）
    var isStormyEvening: Bool {
        Self.stormWeatherCodes.contains(weatherCode) || weatherLabel.contains("雷")
    }

    /// 心情模式推荐的活动
    var moodRecommendedActivity: WorkoutPlanType {
        isRainyAtEvening ? .swimming : .dance
    }

    var moodRecommendedLabel: String {
        moodRecommendedActivity.label
    }

    private static let rainWeatherCodes: Set<Int> = [
        51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99
    ]

    private static let stormWeatherCodes: Set<Int> = [95, 96, 99]
}

struct WeeklyWeatherSnapshot: Sendable, Equatable {
    var cityLabel: String
    var latitude: Double
    var longitude: Double
    var days: [WeatherDayForecast]
    var fetchedAt: Date

    static let empty = WeeklyWeatherSnapshot(
        cityLabel: "",
        latitude: 0,
        longitude: 0,
        days: [],
        fetchedAt: .distantPast
    )

    var isValid: Bool { !days.isEmpty }

    func day(forWeekday weekday: Int) -> WeatherDayForecast? {
        days.first { $0.weekday == weekday }
    }

    /// 心情模式：按 weekday 决定舞蹈或游泳
    static func moodActivity(forWeekday weekday: Int, weather: WeeklyWeatherSnapshot?) -> WorkoutPlanType {
        guard let weather, weather.isValid, let day = weather.day(forWeekday: weekday) else {
            return .dance
        }
        return day.moodRecommendedActivity
    }

    /// 供 AI 心情模式排课
    func formatForMoodWorkoutAI(sessionsNeeded: Int, preferredHour: Int = 19) -> String {
        guard isValid else {
            return """
            【心情模式 · 本地天气】暂无数据。
            默认规则：工作日晚间 \(preferredHour):00 排课；有雨→游泳（notes 含备物清单），无雨→舞蹈。
            """
        }

        var lines: [String] = []
        lines.append("【心情模式 · 本地一周天气 · \(cityLabel.isEmpty ? "当前位置" : cityLabel)】")
        lines.append("核心规则：**下雨/高降水 → 游泳**（雨天和游泳更搭，notes 必须写备物：\(MoodWorkoutTips.swimmingPackingList)）；**否则 → 舞蹈**。")
        lines.append("优先工作日晚间约 \(preferredHour):00（dayOfWeek 2–6）；共排 \(sessionsNeeded) 场，可按日混合舞蹈与游泳。")

        let weekdaySlots = [2, 4, 3, 5, 6, 7].prefix(sessionsNeeded)
        let picks = weekdaySlots.map { day -> String in
            let activity = Self.moodActivity(forWeekday: day, weather: self)
            let label = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][day]
            return "\(label)→\(activity.label)"
        }.joined(separator: " · ")
        lines.append("规则引擎建议：\(picks)")

        for day in days {
            let flag = day.isRainyAtEvening ? "🌧→游泳" : "☀→舞蹈"
            lines.append("\(day.weekdayLabel) 19:00 · \(day.eveningSummary) · \(flag)")
        }
        return lines.joined(separator: "\n")
    }

    /// 供 AI 排课：优先推荐 evening 天气适宜的工作日
    func formatForWorkoutAI(
        sessionsNeeded: Int,
        activityLabel: String,
        preferredHour: Int = 19
    ) -> String {
        guard isValid else {
            return "【本地天气】暂无数据，请按工作日 19:00 左右默认安排 \(activityLabel)。"
        }

        var lines: [String] = []
        lines.append("【本地一周天气 · \(cityLabel.isEmpty ? "当前位置" : cityLabel)】")
        lines.append("用户下班后约 \(preferredHour):00 进行 \(activityLabel)，请优先选「适宜」日期，并在 notes 写明建议开始时间与天气理由。")

        let goodDays = days.filter(\.isGoodForEveningActivity)
        if goodDays.isEmpty {
            lines.append("本周晚间天气整体一般，仍需排满 \(sessionsNeeded) 场，选相对最好的日期并提醒备雨/室内。")
        } else {
            let picks = goodDays.prefix(sessionsNeeded).map(\.weekdayLabel).joined(separator: "、")
            lines.append("推荐优先安排：\(picks)（共需 \(sessionsNeeded) 场）")
        }

        for day in days {
            let flag = day.isGoodForEveningActivity ? "✓适宜" : "△一般"
            lines.append("\(day.weekdayLabel) \(day.date.formatted(date: .abbreviated, time: .omitted)) 19:00 · \(day.eveningSummary) · \(flag)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Open-Meteo 天气客户端
enum WeatherService {

    private static let eveningHour = 19

    @MainActor
    static func fetchWeeklyEveningForecast(
        location: CLLocation,
        geocoder: CLGeocoder = CLGeocoder()
    ) async -> WeeklyWeatherSnapshot {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        var cityLabel = String(format: "%.2f°N, %.2f°E", lat, lon)

        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            let locality = placemark.locality ?? placemark.subLocality ?? ""
            let admin = placemark.administrativeArea ?? ""
            let joined = [locality, admin].filter { !$0.isEmpty }.joined(separator: " ")
            if !joined.isEmpty { cityLabel = joined }
        }

        guard let url = forecastURL(latitude: lat, longitude: lon) else {
            return WeeklyWeatherSnapshot(
                cityLabel: cityLabel,
                latitude: lat,
                longitude: lon,
                days: [],
                fetchedAt: Date()
            )
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let days = parseOpenMeteo(data: data)
            return WeeklyWeatherSnapshot(
                cityLabel: cityLabel,
                latitude: lat,
                longitude: lon,
                days: days,
                fetchedAt: Date()
            )
        } catch {
            return WeeklyWeatherSnapshot(
                cityLabel: cityLabel,
                latitude: lat,
                longitude: lon,
                days: [],
                fetchedAt: Date()
            )
        }
    }

    @MainActor
    static func fetchWeeklyEveningForecast(locationService: LocationService) async -> WeeklyWeatherSnapshot {
        guard let location = await locationService.fetchCurrentLocation() else {
            return .empty
        }
        return await fetchWeeklyEveningForecast(location: location)
    }

    // MARK: - Private

    private static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "8")
        ]
        return components?.url
    }

    private static func parseOpenMeteo(data: Data) -> [WeatherDayForecast] {
        struct Payload: Decodable {
            struct Hourly: Decodable {
                let time: [String]
                let temperature_2m: [Double?]
                let precipitation_probability: [Int?]
                let weather_code: [Int?]
            }
            let hourly: Hourly
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let calendar = Calendar.current
        let weekdayLabels = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]

        var byDay: [String: (temp: Double?, precip: Int?, code: Int, date: Date)] = [:]

        for (index, timeString) in payload.hourly.time.enumerated() {
            guard let date = formatter.date(from: timeString) else { continue }
            let hour = calendar.component(.hour, from: date)
            guard hour == eveningHour else { continue }

            let dayKey = calendar.startOfDay(for: date).timeIntervalSince1970.description
            let temp = payload.hourly.temperature_2m[safe: index] ?? nil
            let precip = payload.hourly.precipitation_probability[safe: index] ?? nil
            let code = payload.hourly.weather_code[safe: index].flatMap { $0 } ?? 0

            if byDay[dayKey] == nil {
                byDay[dayKey] = (temp: temp, precip: precip, code: code, date: calendar.startOfDay(for: date))
            }
        }

        let todayStart = calendar.startOfDay(for: Date())
        return byDay.values
            .sorted { $0.date < $1.date }
            .filter { $0.date >= todayStart }
            .prefix(7)
            .map { item in
                let weekday = calendar.component(.weekday, from: item.date)
                let precip = item.precip ?? 50
                let good = isGoodEvening(tempC: item.temp, precipPercent: precip, code: item.code)
                return WeatherDayForecast(
                    id: item.date.formatted(date: .numeric, time: .omitted),
                    date: item.date,
                    weekday: weekday,
                    weekdayLabel: weekdayLabels[safe: weekday] ?? "周?",
                    eveningTempC: item.temp,
                    eveningPrecipPercent: item.precip,
                    weatherCode: item.code,
                    weatherLabel: weatherLabel(for: item.code),
                    isGoodForEveningActivity: good
                )
            }
    }

    private static func isGoodEvening(tempC: Double?, precipPercent: Int, code: Int) -> Bool {
        if precipPercent >= 55 { return false }
        if [95, 96, 99].contains(code) { return false }
        if let temp = tempC {
            if temp < 0 || temp > 36 { return false }
        }
        return precipPercent < 40
    }

    private static func weatherLabel(for code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2, 3: return "多云"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "雨"
        case 71, 73, 75, 77: return "雪"
        case 80, 81, 82: return "阵雨"
        case 95, 96, 99: return "雷暴"
        default: return "一般"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
