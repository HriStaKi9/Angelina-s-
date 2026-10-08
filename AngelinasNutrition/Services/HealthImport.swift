import Foundation

/// A body measurement read from Apple Health.
struct HealthMeasurement: Equatable {
    /// The Health sample's UUID, used to import each sample only once.
    let id: String
    let field: CheckInField
    let value: Double
    let date: Date
}

enum HealthImport {
    /// One check-in per day with the latest value of each measurement, skipping samples imported before.
    static func checkIns(from samples: [HealthMeasurement], alreadyImported: Set<String>, logID: String,
                         calendar: Calendar = .current) -> (checkIns: [CheckIn], importedIDs: Set<String>) {
        let fresh = samples.filter { !alreadyImported.contains($0.id) }
        let byDay = Dictionary(grouping: fresh) { calendar.startOfDay(for: $0.date) }
        let checkIns = byDay.keys.sorted().map { day -> CheckIn in
            let items = byDay[day, default: []].sorted { $0.date < $1.date }
            var checkIn = CheckIn(planID: logID, date: items.last?.date ?? day)
            for item in items { checkIn.set(item.field, (item.value * 10).rounded() / 10) }
            return checkIn
        }
        return (checkIns, Set(fresh.map(\.id)))
    }

    static var importedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "health.importedSamples") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "health.importedSamples") }
    }

    /// Diary entries are stored per day; Health needs a time. Today uses "now", past days noon.
    static func date(forDayKey key: String, now: Date = .now, calendar: Calendar = .current) -> Date {
        if key == FoodDiaryStore.dayKey(now, calendar: calendar) { return now }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return now }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? now
    }
}
