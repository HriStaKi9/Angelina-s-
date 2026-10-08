import Foundation
import HealthKit
import Observation

/// Apple Health: reads steps, activity and body measurements; writes measurements, the food diary
/// and logged workouts. Everything is opt-in and stays on the phone.
@Observable
final class HealthService {
    struct Activity: Equatable {
        var steps: Double = 0
        var stepsWeekAverage: Double = 0
        var activeEnergy: Double = 0
        var distanceKm: Double = 0
    }

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    /// The user tapped "Connect" (iOS never says which read types were allowed).
    private(set) var isConnected = UserDefaults.standard.bool(forKey: "health.connected")
    var writeMeasurements = UserDefaults.standard.object(forKey: "health.writeMeasurements") as? Bool ?? true {
        didSet { UserDefaults.standard.set(writeMeasurements, forKey: "health.writeMeasurements") }
    }
    var writeDiary = UserDefaults.standard.object(forKey: "health.writeDiary") as? Bool ?? true {
        didSet { UserDefaults.standard.set(writeDiary, forKey: "health.writeDiary") }
    }
    var writeWorkouts = UserDefaults.standard.object(forKey: "health.writeWorkouts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(writeWorkouts, forKey: "health.writeWorkouts") }
    }
    private(set) var activity = Activity()

    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let bodyFat = HKQuantityType(.bodyFatPercentage)
    private static let waist = HKQuantityType(.waistCircumference)
    private static let dietary: [HKQuantityType] = [
        HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal),
    ]

    // MARK: Connect

    func connect() async throws {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning),
            Self.bodyMass, Self.bodyFat, Self.waist, HKObjectType.workoutType(),
        ]
        let share: Set<HKSampleType> = Set([Self.bodyMass, Self.bodyFat, Self.waist, HKObjectType.workoutType()] + Self.dietary)
        try await store.requestAuthorization(toShare: share, read: read)
        isConnected = true
        UserDefaults.standard.set(true, forKey: "health.connected")
        await refreshActivity()
    }

    func disconnect() {
        // Apps can't revoke Health permissions; this just stops reading and writing.
        isConnected = false
        UserDefaults.standard.set(false, forKey: "health.connected")
        activity = Activity()
    }

    // MARK: Activity

    func refreshActivity(now: Date = .now) async {
        guard isConnected, isAvailable else { return }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: startOfDay) ?? startOfDay
        var updated = Activity()
        updated.steps = await sum(.stepCount, from: startOfDay, to: now, unit: .count())
        // Average of the last 7 full days.
        updated.stepsWeekAverage = await sum(.stepCount, from: weekStart, to: startOfDay, unit: .count()) / 7
        updated.activeEnergy = await sum(.activeEnergyBurned, from: startOfDay, to: now, unit: .kilocalorie())
        updated.distanceKm = await sum(.distanceWalkingRunning, from: startOfDay, to: now, unit: .meterUnit(with: .kilo))
        activity = updated
    }

    private func sum(_ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date, unit: HKUnit) async -> Double {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum)
        let result = try? await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    // MARK: Body measurements

    /// Weight, body fat and waist recorded by other apps and devices (e.g. a smart scale) since `since`.
    func bodySamples(since: Date) async -> [HealthMeasurement] {
        guard isConnected, isAvailable else { return [] }
        let ownBundle = Bundle.main.bundleIdentifier
        var result: [HealthMeasurement] = []
        for (type, field, unit) in [(Self.bodyMass, CheckInField.weight, HKUnit.gramUnit(with: .kilo)),
                                    (Self.bodyFat, .bodyFat, .percent()),
                                    (Self.waist, .waist, .meterUnit(with: .centi))] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: since, end: .now))],
                sortDescriptors: [SortDescriptor(\.endDate)])
            let samples = (try? await descriptor.result(for: store)) ?? []
            for sample in samples where sample.sourceRevision.source.bundleIdentifier != ownBundle {
                var value = sample.quantity.doubleValue(for: unit)
                if field == .bodyFat { value *= 100 }
                result.append(HealthMeasurement(id: sample.uuid.uuidString, field: field, value: value, date: sample.endDate))
            }
        }
        return result
    }

    func save(_ checkIn: CheckIn) async {
        guard isConnected, writeMeasurements, isAvailable else { return }
        let metadata: [String: Any] = [HKMetadataKeyExternalUUID: checkIn.id.uuidString]
        var samples: [HKQuantitySample] = []
        if let weight = checkIn.weight {
            samples.append(HKQuantitySample(type: Self.bodyMass, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight),
                                            start: checkIn.date, end: checkIn.date, metadata: metadata))
        }
        if let fat = checkIn.value(.bodyFat) {
            samples.append(HKQuantitySample(type: Self.bodyFat, quantity: HKQuantity(unit: .percent(), doubleValue: fat / 100),
                                            start: checkIn.date, end: checkIn.date, metadata: metadata))
        }
        if let waist = checkIn.waist {
            samples.append(HKQuantitySample(type: Self.waist, quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: waist),
                                            start: checkIn.date, end: checkIn.date, metadata: metadata))
        }
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    // MARK: Food diary

    /// Saves a diary entry as a Health food entry (calories and macros), tagged with the entry's id.
    func save(_ entry: DiaryEntry, date: Date) async {
        guard isConnected, writeDiary, isAvailable else { return }
        let metadata: [String: Any] = [HKMetadataKeyExternalUUID: entry.id.uuidString, HKMetadataKeyFoodType: entry.name.en]
        let n = entry.nutrients
        let values: [(HKQuantityType, HKUnit, Double?)] = [
            (Self.dietary[0], .kilocalorie(), n.kcal), (Self.dietary[1], .gram(), n.protein),
            (Self.dietary[2], .gram(), n.carbs), (Self.dietary[3], .gram(), n.fat),
        ]
        let samples: Set<HKSample> = Set(values.compactMap { type, unit, value in
            guard let value, value > 0 else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date, metadata: metadata)
        })
        guard !samples.isEmpty else { return }
        let food = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: samples, metadata: metadata)
        try? await store.save(food)
    }

    /// Removes a deleted diary entry from Health.
    func deleteDiaryEntry(id: UUID) async {
        guard isConnected, isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.uuidString])
        for type in Self.dietary as [HKObjectType] + [HKCorrelationType(.food)] {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    // MARK: Workouts

    func saveWorkout(start: Date, end: Date, title: String) async {
        guard isConnected, writeWorkouts, isAvailable, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: title])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
        }
    }
}
