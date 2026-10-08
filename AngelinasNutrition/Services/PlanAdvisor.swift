import Foundation

/// One program week of check-ins, averaged the way the plans ask ("look at the weekly average").
struct WeekSummary: Equatable, Identifiable {
    let week: Int
    let values: [CheckInField: Double]
    let count: Int

    var id: Int { week }
    var weight: Double? { values[.weight] }
    var waist: Double? { values[.waist] }
    var hips: Double? { values[.hips] }
    var steps: Double? { values[.steps] }

    func value(_ field: CheckInField) -> Double? { values[field] }
}

struct PlanAdvice: Equatable {
    enum Status: Equatable {
        /// Not enough data yet; `weeksNeeded` more weeks of weigh-ins.
        case collecting(weeksNeeded: Int)
        case matched(AdjustmentTable.Row)
        /// Data exists but sits between the plan's rows.
        case noRule
    }

    let status: Status
    /// Weekly change in average weight (kg), most recent week vs the one before.
    let weeklyChange: Double?
}

/// Matches weekly check-in averages to the plan's "what you see → what to do" table.
enum PlanAdvisor {
    static func weeklySummaries(_ checkIns: [CheckIn], programStart: Date, calendar: Calendar = .current) -> [WeekSummary] {
        let grouped = Dictionary(grouping: checkIns) {
            TrainingProgram.weekIndex(of: $0.date, startedOn: programStart, calendar: calendar) + 1
        }
        return grouped.keys.sorted().map { week in
            let items = grouped[week, default: []].sorted { $0.date < $1.date }
            func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
            var values: [CheckInField: Double] = [:]
            for field in CheckInField.allCases {
                let all = items.compactMap { $0.value(field) }
                // Weight and steps are averaged; tape measurements are weekly, so the latest one counts.
                values[field] = field.isAveraged ? average(all) : all.last
            }
            return WeekSummary(week: week, values: values, count: items.count)
        }
    }

    static func advice(table: AdjustmentTable?, checkIns: [CheckIn], programStart: Date, currentWeek: Int,
                       now: Date = .now, calendar: Calendar = .current) -> PlanAdvice {
        let weeks = weeklySummaries(checkIns, programStart: programStart, calendar: calendar)
        let weighted = weeks.filter { $0.weight != nil }
        let change: Double? = weighted.count >= 2
            ? weighted[weighted.count - 1].weight! - weighted[weighted.count - 2].weight!
            : nil

        guard let rows = table?.rows else { return PlanAdvice(status: .noRule, weeklyChange: change) }

        // Symptoms come first: the plans say to act on them straight away.
        let recentFlags = Set(checkIns
            .filter { now.timeIntervalSince($0.date) < 7 * 24 * 3600 }
            .flatMap(\.flags))
        if let row = rows.first(where: { row in
            guard let trigger = row.trigger, trigger.type == .flags else { return false }
            return !(trigger.anyOf ?? []).filter(recentFlags.contains).isEmpty
        }) {
            return PlanAdvice(status: .matched(row), weeklyChange: change)
        }

        guard let change else {
            return PlanAdvice(status: .collecting(weeksNeeded: max(1, 2 - weighted.count)), weeklyChange: nil)
        }

        let ordered: [AdviceTrigger.Kind] = [.losing, .gaining, .stalled, .onTrack, .steady]
        for kind in ordered {
            for row in rows where row.trigger?.type == kind {
                if matches(row.trigger!, change: change, weighted: weighted, currentWeek: currentWeek) {
                    return PlanAdvice(status: .matched(row), weeklyChange: change)
                }
            }
        }
        return PlanAdvice(status: .noRule, weeklyChange: change)
    }

    private static func matches(_ trigger: AdviceTrigger, change: Double, weighted: [WeekSummary], currentWeek: Int) -> Bool {
        switch trigger.type {
        case .losing:
            if let after = trigger.afterWeek, currentWeek <= after { return false }
            return change < -(trigger.perWeek ?? 0)
        case .gaining:
            let span = trigger.weeks ?? 3
            guard weighted.count > span else { return false }
            let window = Array(weighted.suffix(span + 1))
            let weightRising = zip(window, window.dropFirst()).allSatisfy { $1.weight! > $0.weight! }
            guard weightRising else { return false }
            guard trigger.withWaist == true else { return true }
            let waists = window.compactMap(\.waist)
            return waists.count >= 2 && waists.last! > waists.first!
        case .stalled:
            let span = trigger.weeks ?? 2
            guard weighted.count > span else { return false }
            let window = Array(weighted.suffix(span + 1))
            return abs(window.last!.weight! - window.first!.weight!) < 0.2
        case .onTrack:
            return change <= -(trigger.minLossPerWeek ?? 0) && change >= -(trigger.maxLossPerWeek ?? .infinity)
        case .steady:
            return change <= (trigger.maxGainPerWeek ?? 0) && change >= -(trigger.maxLossPerWeek ?? .infinity)
        case .flags:
            return false
        }
    }
}
