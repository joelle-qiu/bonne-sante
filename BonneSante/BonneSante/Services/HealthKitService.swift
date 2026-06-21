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

struct WeightRecord: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double // kg
}

/// 身体档案快照（来自 HealthKit，供目标设置预填）
/// @author jiali.qiu
struct BodyProfileSnapshot: Sendable, Equatable {
    var heightCm: Double?
    var age: Int?
    var gender: String?
    var currentWeightKg: Double?

    static let empty = BodyProfileSnapshot(
        heightCm: nil,
        age: nil,
        gender: nil,
        currentWeightKg: nil
    )

    var hasAnyData: Bool {
        heightCm != nil || age != nil || gender != nil || currentWeightKg != nil
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
    @Published var menstrualSnapshot: MenstrualCycleSnapshot = .empty

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
            HKQuantityType(.height)
        ]
        if let menstrual = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) {
            typesToRead.insert(menstrual)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            await fetchTodayCaloriesBurned()
            await fetchWeightHistory()
            await fetchBodyProfile()
            await fetchMenstrualCycleSnapshot()
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

        bodyProfile = BodyProfileSnapshot(
            heightCm: await fetchLatestHeightCm(),
            age: fetchAgeFromDateOfBirth(),
            gender: fetchGenderFromBiologicalSex(),
            currentWeightKg: currentWeight
        )
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
        guard let components = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else {
            return nil
        }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
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
}
