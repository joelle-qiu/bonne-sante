import Foundation
import HealthKit

/// HealthKit 经期快照（供 CycleEngine 合并）
/// @author jiali.qiu
struct MenstrualCycleSnapshot: Sendable, Equatable {
    var lastPeriodStart: Date?
    var inferredCycleLength: Int?
    var inferredPeriodLength: Int?
    var periodStartDates: [Date]
    var loggedFlowDays: Int

    static let empty = MenstrualCycleSnapshot(
        lastPeriodStart: nil,
        inferredCycleLength: nil,
        inferredPeriodLength: nil,
        periodStartDates: [],
        loggedFlowDays: 0
    )
}

/// 体脂/去脂体重单位归一化（PICOOC 等常将 22% 写为 0.22）
/// @author jiali.qiu
enum BodyCompositionNormalizer {

    /// 将 HealthKit 原始体脂读数统一为 3–65 的百分数
    static func normalizeBodyFatPercent(_ raw: Double?) -> Double? {
        guard let raw, raw > 0 else { return nil }

        var candidates: [Double] = []
        if raw <= 1.0 {
            candidates.append(raw * 100)
        }
        if raw > 1.0, raw <= 65 {
            candidates.append(raw)
        }
        // 少数设备误写为 2600 表示 26%
        if raw > 65, raw <= 6500 {
            candidates.append(raw / 100)
        }

        guard let best = candidates.first(where: { (3...65).contains($0) }) else { return nil }
        return (best * 10).rounded() / 10
    }

    /// 合并体脂秤读数：优先信任 PICOOC 写入的体脂率，仅用体重+去脂体重补全或纠错
    static func reconcile(
        weightKg: Double?,
        bodyFatPercent rawBodyFat: Double?,
        leanBodyMassKg rawLean: Double?
    ) -> (bodyFatPercent: Double?, leanBodyMassKg: Double?) {
        if let direct = normalizeBodyFatPercent(rawBodyFat) {
            var lean = rawLean
            if let weight = weightKg, weight > 30, weight < 300 {
                let expectedLean = weight * (1 - direct / 100)
                if lean == nil {
                    lean = (expectedLean * 10).rounded() / 10
                } else if var currentLean = lean, currentLean > weight * 0.98 || currentLean < weight * 0.45 {
                    currentLean = (expectedLean * 10).rounded() / 10
                    lean = currentLean
                }
            }
            return (direct, lean)
        }

        guard let weight = weightKg, weight > 30, weight < 300,
              let lean = rawLean, lean > 10, lean < weight * 0.98 else {
            return (nil, rawLean)
        }

        let derived = ((weight - lean) / weight) * 100
        guard (3...65).contains(derived) else { return (nil, rawLean) }
        return ((derived * 10).rounded() / 10, lean)
    }

    /// 去脂体重占体重比例是否合理（避免用错体重导致推导离谱体脂）
    static func isPlausibleLeanMass(_ lean: Double, weight: Double) -> Bool {
        let ratio = lean / weight
        return ratio >= 0.45 && ratio <= 0.98
    }
}

struct WeightRecord: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double // kg
}

/// HealthKit 数量样本（含来源与时间，供体成分对齐）
struct HealthQuantitySample: Sendable {
    let value: Double
    let date: Date
    let sourceName: String?
}

/// 身体档案快照（来自 HealthKit，供目标设置预填）
/// @author jiali.qiu
struct BodyProfileSnapshot: Sendable, Equatable {
    var heightCm: Double?
    var age: Int?
    var gender: String?
    var currentWeightKg: Double?
    /// 体脂率（%），来自 Apple 健康
    var bodyFatPercent: Double?
    /// 去脂体重 / lean mass（kg）
    var leanBodyMassKg: Double?
    /// HealthKit 原始体脂读数（调试/设置页展示）
    var bodyFatRawHealthKit: Double?
    var bodyFatMeasuredAt: Date?
    var bodyFatSourceName: String?
    /// 体成分测量时刻的体重（与体脂秤同次读数）
    var compositionWeightKg: Double?

    static let empty = BodyProfileSnapshot(
        heightCm: nil,
        age: nil,
        gender: nil,
        currentWeightKg: nil,
        bodyFatPercent: nil,
        leanBodyMassKg: nil,
        bodyFatRawHealthKit: nil,
        bodyFatMeasuredAt: nil,
        bodyFatSourceName: nil,
        compositionWeightKg: nil
    )

    var hasAnyData: Bool {
        heightCm != nil || age != nil || gender != nil || currentWeightKg != nil
            || bodyFatPercent != nil || leanBodyMassKg != nil
    }

    /// 脂肪量（kg）= 体重 × 体脂率
    var fatMassKg: Double? {
        guard let weight = currentWeightKg, let bodyFat = bodyFatPercent else { return nil }
        return weight * bodyFat / 100
    }
}

struct WorkoutSnapshot: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let activityLabel: String
    let durationMinutes: Double
    let activeCalories: Double
}

/// Apple 健康能量与活动快照（近7日均值 + 今日）
/// @author jiali.qiu
struct EnergyProfileSnapshot: Sendable, Equatable {
    var todayActiveKcal: Double
    var todayBasalKcal: Double
    var avgActiveKcal7d: Double?
    var avgBasalKcal7d: Double?
    var avgSteps7d: Int?
    /// 近7日中有基础代谢读数的天数
    var basalSampleDays7d: Int = 0
    /// 近7日中有活动消耗读数的天数
    var activeSampleDays7d: Int = 0

    static let empty = EnergyProfileSnapshot(
        todayActiveKcal: 0,
        todayBasalKcal: 0,
        avgActiveKcal7d: nil,
        avgBasalKcal7d: nil,
        avgSteps7d: nil,
        basalSampleDays7d: 0,
        activeSampleDays7d: 0
    )

    var hasWatchData: Bool {
        (avgActiveKcal7d ?? todayActiveKcal) > 0 || (avgBasalKcal7d ?? todayBasalKcal) > 0
    }
}

@MainActor
final class HealthKitService: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var activeCaloriesBurned: Double = 0
    @Published var basalCaloriesBurned: Double = 0
    @Published var authorizationError: String?
    @Published var currentWeight: Double?
    @Published var weightHistory: [WeightRecord] = []
    @Published var bodyProfile: BodyProfileSnapshot = .empty
    @Published var energyProfile: EnergyProfileSnapshot = .empty
    @Published var menstrualSnapshot: MenstrualCycleSnapshot = .empty
    @Published var recentWorkouts: [WorkoutSnapshot] = []

    var totalCaloriesBurned: Double {
        activeCaloriesBurned + basalCaloriesBurned
    }

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            authorizationError = "HealthKit is not available on this device."
            return
        }

        var typesToRead: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.stepCount)
        ]
        typesToRead.insert(HKObjectType.workoutType())
        if let menstrual = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) {
            typesToRead.insert(menstrual)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            await fetchTodayCaloriesBurned()
            await fetchWeightHistory()
            await fetchBodyProfile()
            await fetchEnergyProfile()
            await fetchMenstrualCycleSnapshot()
            await fetchRecentWorkouts()
        } catch {
            authorizationError = "Failed to authorize HealthKit: \(error.localizedDescription)"
        }
    }

    func fetchTodayCaloriesBurned() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchActiveCalories()
            }
            group.addTask {
                await self.fetchBasalCalories()
            }
        }
        energyProfile.todayActiveKcal = activeCaloriesBurned
        energyProfile.todayBasalKcal = basalCaloriesBurned
    }

    /// 读取近 7 日能量与步数均值（比单日 Watch 数据更稳定）
    func fetchEnergyProfile() async {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) else { return }

        var activeDaily: [Double] = []
        var basalDaily: [Double] = []
        var stepDaily: [Double] = []

        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            async let active = fetchCaloriesBetween(identifier: .activeEnergyBurned, start: dayStart, end: dayEnd)
            async let basal = fetchCaloriesBetween(identifier: .basalEnergyBurned, start: dayStart, end: dayEnd)
            async let steps = fetchStepsBetween(start: dayStart, end: dayEnd)
            let (a, b, s) = await (active, basal, steps)
            if a > 0 { activeDaily.append(a) }
            if b > 0 { basalDaily.append(b) }
            if s > 0 { stepDaily.append(s) }
        }

        energyProfile.todayActiveKcal = activeCaloriesBurned
        energyProfile.todayBasalKcal = basalCaloriesBurned
        energyProfile.basalSampleDays7d = basalDaily.count
        energyProfile.activeSampleDays7d = activeDaily.count
        energyProfile.avgActiveKcal7d = activeDaily.count >= 3 ? average(activeDaily) : nil
        energyProfile.avgBasalKcal7d = basalDaily.count >= 3 ? average(basalDaily) : nil
        if let avgSteps = average(stepDaily) {
            energyProfile.avgSteps7d = Int(avgSteps.rounded())
        } else {
            energyProfile.avgSteps7d = nil
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func fetchCaloriesBetween(
        identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date
    ) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    private func fetchStepsBetween(start: Date, end: Date) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    func fetchMenstrualCycleSnapshot(monthsBack: Int = 6) async {
        guard let categoryType = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else {
            menstrualSnapshot = .empty
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        menstrualSnapshot = Self.buildMenstrualSnapshot(from: samples, calendar: calendar)
    }

    // MARK: - Menstrual Parsing

    nonisolated static func buildMenstrualSnapshot(
        from samples: [HKCategorySample],
        calendar: Calendar = .current
    ) -> MenstrualCycleSnapshot {
        let flowDays = Set(
            samples
                .filter { isFlowDay($0) }
                .map { calendar.startOfDay(for: $0.startDate) }
        )
        .sorted()

        guard !flowDays.isEmpty else { return .empty }

        var periodStarts: [Date] = []
        var periodLengths: [Int] = []
        var currentStart: Date?
        var previousDay: Date?

        for day in flowDays {
            if let prev = previousDay,
               let gap = calendar.dateComponents([.day], from: prev, to: day).day,
               gap > 1 {
                if let start = currentStart, let end = previousDay {
                    periodStarts.append(start)
                    periodLengths.append(calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 } ?? 1)
                }
                currentStart = day
            } else if currentStart == nil {
                currentStart = day
            }
            previousDay = day
        }

        if let start = currentStart, let end = previousDay {
            periodStarts.append(start)
            periodLengths.append(calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 } ?? 1)
        }

        let cycleLengths: [Int] = zip(periodStarts, periodStarts.dropFirst()).compactMap { lhs, rhs in
            calendar.dateComponents([.day], from: lhs, to: rhs).day
        }

        return MenstrualCycleSnapshot(
            lastPeriodStart: periodStarts.last,
            inferredCycleLength: averageRounded(cycleLengths, defaultValue: nil),
            inferredPeriodLength: averageRounded(periodLengths, defaultValue: nil),
            periodStartDates: periodStarts,
            loggedFlowDays: flowDays.count
        )
    }

    nonisolated private static func isFlowDay(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueMenstrualFlow(rawValue: sample.value) else { return false }
        return value != .none
    }

    nonisolated private static func averageRounded(_ values: [Int], defaultValue: Int?) -> Int? {
        guard !values.isEmpty else { return defaultValue }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return Int(avg.rounded())
    }

    private func fetchActiveCalories() async {
        let calories = await fetchCalories(for: .activeEnergyBurned)
        activeCaloriesBurned = calories
    }

    private func fetchBasalCalories() async {
        let calories = await fetchCalories(for: .basalEnergyBurned)
        basalCaloriesBurned = calories
    }

    private func fetchCalories(for identifier: HKQuantityTypeIdentifier) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return 0
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let sum = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Body Profile

    /// 读取身高、年龄、性别与最新体重，供目标设置预填
    func fetchBodyProfile() async {
        if currentWeight == nil {
            await fetchWeightHistory(days: 30)
        }

        let bodyFatSample = await fetchLatestQuantitySample(
            identifier: .bodyFatPercentage,
            unit: .percent()
        )
        let leanSample = await fetchLatestQuantitySample(
            identifier: .leanBodyMass,
            unit: .gramUnit(with: .kilo)
        )

        let compositionAnchor = bodyFatSample?.date ?? leanSample?.date
        let compositionWeight: Double?
        if let anchor = compositionAnchor {
            compositionWeight = await fetchWeightNear(date: anchor)
        } else {
            compositionWeight = nil
        }
        let weightForComposition = compositionWeight ?? currentWeight

        let reconciled = BodyCompositionNormalizer.reconcile(
            weightKg: weightForComposition,
            bodyFatPercent: bodyFatSample?.value,
            leanBodyMassKg: leanSample?.value
        )

        bodyProfile = BodyProfileSnapshot(
            heightCm: await fetchLatestHeightCm(),
            age: fetchAgeFromDateOfBirth(),
            gender: fetchGenderFromBiologicalSex(),
            currentWeightKg: currentWeight,
            bodyFatPercent: reconciled.bodyFatPercent,
            leanBodyMassKg: reconciled.leanBodyMassKg,
            bodyFatRawHealthKit: bodyFatSample?.value,
            bodyFatMeasuredAt: bodyFatSample?.date ?? leanSample?.date,
            bodyFatSourceName: bodyFatSample?.sourceName ?? leanSample?.sourceName,
            compositionWeightKg: weightForComposition
        )
    }

    /// 取测量时刻 ±24h 内最接近的体重（与 PICOOC 同次上秤读数对齐）
    private func fetchWeightNear(date: Date, window: TimeInterval = 86400) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }
        let start = date.addingTimeInterval(-window)
        let end = date.addingTimeInterval(window)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let nearest = samples.min { lhs, rhs in
                    abs(lhs.startDate.timeIntervalSince(date)) < abs(rhs.startDate.timeIntervalSince(date))
                }
                let kg = nearest?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestQuantitySample(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> HealthQuantitySample? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let source = sample.sourceRevision.source.name
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: HealthQuantitySample(
                    value: value,
                    date: sample.startDate,
                    sourceName: source
                ))
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestBodyFatPercent() async -> Double? {
        await fetchLatestQuantitySample(identifier: .bodyFatPercentage, unit: .percent())?.value
    }

    private func fetchLatestLeanBodyMassKg() async -> Double? {
        await fetchLatestQuantitySample(identifier: .leanBodyMass, unit: .gramUnit(with: .kilo))?.value
    }

    private func fetchLatestQuantitySample(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestHeightCm() async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .height) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let heightCm = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: heightCm)
            }
            healthStore.execute(query)
        }
    }

    private func fetchAgeFromDateOfBirth() -> Int? {
        let components: DateComponents
        do {
            components = try healthStore.dateOfBirthComponents()
        } catch {
            return nil
        }

        let calendar = Calendar.current
        if let birthDate = calendar.date(from: components),
           let age = calendar.dateComponents([.year], from: birthDate, to: Date()).year,
           (16...100).contains(age) {
            return age
        }

        // 仅填写出生年份时仍可估算
        if let birthYear = components.year {
            let currentYear = calendar.component(.year, from: Date())
            let age = currentYear - birthYear
            if (16...100).contains(age) { return age }
        }
        return nil
    }

    private func fetchGenderFromBiologicalSex() -> String? {
        guard let sexObject = try? healthStore.biologicalSex() else { return nil }
        switch sexObject.biologicalSex {
        case .female: return "female"
        case .male: return "male"
        default: return nil
        }
    }

    // MARK: - Weight Data

    func fetchWeightHistory(days: Int = 90) async {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return
        }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, _ in
                Task { @MainActor in
                    guard let samples = samples as? [HKQuantitySample] else {
                        continuation.resume()
                        return
                    }

                    self?.weightHistory = samples.map { sample in
                        WeightRecord(
                            date: sample.startDate,
                            weight: sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                        )
                    }

                    self?.currentWeight = self?.weightHistory.first?.weight

                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    var dailyWeights: [WeightRecord] {
        let grouped = Dictionary(grouping: weightHistory) { record in
            Calendar.current.startOfDay(for: record.date)
        }

        return grouped.map { (_, records) in
            let avgWeight = records.reduce(0) { $0 + $1.weight } / Double(records.count)
            return WeightRecord(date: records.first!.date, weight: avgWeight)
        }.sorted { $0.date < $1.date }
    }

    /// 读取近 N 天 Apple 健康锻炼记录
    func fetchRecentWorkouts(days: Int = 14) async {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let snapshots = await loadWorkouts(from: start, to: Date(), limit: 120)
        recentWorkouts = snapshots
    }

    /// 读取指定时间范围内的锻炼记录并更新 recentWorkouts 缓存
    func fetchWorkouts(from start: Date, to end: Date, limit: Int = 120) async {
        recentWorkouts = await loadWorkouts(from: start, to: end, limit: limit)
    }

    /// 读取锻炼历史（供偏好推断，不覆盖 recentWorkouts）
    func fetchWorkoutHistory(days: Int = 90, limit: Int = 500) async -> [WorkoutSnapshot] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return await loadWorkouts(from: start, to: Date(), limit: limit)
    }

    /// 读取指定时间范围内的锻炼记录
    private func loadWorkouts(from start: Date, to end: Date, limit: Int) async -> [WorkoutSnapshot] {
        guard isHealthKitAvailable else {
            return []
        }

        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        return samples.map { Self.snapshot(from: $0) }
    }

    private static func snapshot(from workout: HKWorkout) -> WorkoutSnapshot {
        WorkoutSnapshot(
            id: UUID(),
            date: workout.startDate,
            activityLabel: workoutLabel(for: workout.workoutActivityType),
            durationMinutes: workout.duration / 60,
            activeCalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
        )
    }

    static func workoutLabel(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .yoga: return "瑜伽"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "HIIT"
        case .pilates: return "普拉提"
        case .hiking: return "徒步"
        case .elliptical: return "椭圆机"
        default: return "锻炼"
        }
    }
}
