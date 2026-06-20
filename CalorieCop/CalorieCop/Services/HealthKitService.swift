import Foundation
import HealthKit

struct WeightRecord: Identifiable {
    let id = UUID()
    let date: Date
    let weight: Double // kg
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

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.bodyMass)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            await fetchTodayCaloriesBurned()
            await fetchWeightHistory()
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

                    // Set current weight as most recent
                    self?.currentWeight = self?.weightHistory.first?.weight

                    continuation.resume()
                }
            }
            healthStore.execute(query)
        }
    }

    // Get daily average weights for charting
    var dailyWeights: [WeightRecord] {
        let grouped = Dictionary(grouping: weightHistory) { record in
            Calendar.current.startOfDay(for: record.date)
        }

        return grouped.map { (date, records) in
            let avgWeight = records.reduce(0) { $0 + $1.weight } / Double(records.count)
            return WeightRecord(date: date, weight: avgWeight)
        }.sorted { $0.date < $1.date }
    }
}
