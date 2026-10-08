import Foundation

/// Equipment the user trains with; filters the exercise database to what they can actually do.
enum HomeGear: String, Codable, CaseIterable, Identifiable {
    case powerRack, barbell, bench, dumbbells, pullUpBar, bands, kettlebells, gym

    var id: String { rawValue }

    static let defaultSet: Set<HomeGear> = [.powerRack, .barbell, .bench, .dumbbells, .pullUpBar, .bands]

    var title: Localized {
        switch self {
        case .powerRack: Localized(bg: "Рак (power rack)", en: "Power rack")
        case .barbell: Localized(bg: "Щанга", en: "Barbell")
        case .bench: Localized(bg: "Пейка", en: "Bench")
        case .dumbbells: Localized(bg: "Дъмбели", en: "Dumbbells")
        case .pullUpBar: Localized(bg: "Лост за набиране", en: "Pull-up bar")
        case .bands: Localized(bg: "Ластици", en: "Bands")
        case .kettlebells: Localized(bg: "Пудовка", en: "Kettlebell")
        case .gym: Localized(bg: "Фитнес (скрипци, машини)", en: "Gym (cables, machines)")
        }
    }

    var systemImage: String {
        switch self {
        case .powerRack: "square.split.2x1"
        case .barbell, .dumbbells: "dumbbell.fill"
        case .bench: "rectangle.portrait.bottomhalf.filled"
        case .pullUpBar: "figure.climbing"
        case .bands: "lasso"
        case .kettlebells: "scalemass.fill"
        case .gym: "building.2.fill"
        }
    }
}

extension Exercise {
    /// Whether this exercise can be done with the given equipment. The database only records the main
    /// implement, so rack, bench and bar needs are inferred from the exercise name.
    func isDoable(with gear: Set<HomeGear>) -> Bool {
        if gear.contains(.gym) { return true }
        let name = self.name.lowercased()
        let hasBar = gear.contains(.pullUpBar) || gear.contains(.powerRack)
        let needsBench = ["bench", "incline", "decline", "seated"].contains { name.contains($0) } && !name.contains("floor")
        if needsBench && !gear.contains(.bench) { return false }
        let hangs = ["pull-up", "pullup", "chin-up", "hanging", "muscle up"].contains { name.contains($0) }

        switch resolvedEquipment {
        case .bodyOnly:
            if hangs { return hasBar }
            if name.contains("dip") { return false }
            if name.contains("inverted row") { return gear.contains(.powerRack) && gear.contains(.barbell) }
            return true
        case .barbell, .ezCurlBar:
            guard gear.contains(.barbell) else { return false }
            // Bar on the back or unracked over a bench needs a rack (or stands).
            let needsRack = ["squat", "bench press", "military press", "shoulder press", "pin", "rack", "good morning", "lunge"]
                .contains { name.contains($0) }
            return !needsRack || gear.contains(.powerRack)
        case .dumbbell:
            return gear.contains(.dumbbells)
        case .kettlebells:
            return gear.contains(.kettlebells)
        case .bands:
            return gear.contains(.bands)
        case .other:
            return name.contains("band assisted pull-up") && gear.contains(.bands) && hasBar
        case .cable, .machine, .medicineBall, .exerciseBall, .foamRoll:
            return false
        }
    }
}

/// Hand-picked exercises that make the most of a power rack, grouped by movement.
enum PowerRackCollection {
    struct Group: Identifiable {
        let id: String
        let title: Localized
        let exerciseIDs: [String]
    }

    static let groups: [Group] = [
        Group(id: "squat", title: Localized(bg: "Клекове", en: "Squats"),
              exerciseIDs: ["Barbell_Squat", "Box_Squat", "Barbell_Full_Squat", "Front_Barbell_Squat", "Barbell_Lunge", "Barbell_Step_Ups"]),
        Group(id: "hinge", title: Localized(bg: "Седалище и задно бедро", en: "Glutes & hinge"),
              exerciseIDs: ["Barbell_Hip_Thrust", "Barbell_Glute_Bridge", "Romanian_Deadlift", "Barbell_Deadlift", "Rack_Pulls", "Good_Morning_off_Pins", "Sumo_Deadlift"]),
        Group(id: "press", title: Localized(bg: "Преси", en: "Presses"),
              exerciseIDs: ["Barbell_Bench_Press_-_Medium_Grip", "Barbell_Incline_Bench_Press_-_Medium_Grip", "Close-Grip_Barbell_Bench_Press", "Pin_Presses", "Floor_Press", "Standing_Military_Press", "Seated_Barbell_Military_Press"]),
        Group(id: "pull", title: Localized(bg: "Гръб и набирания", en: "Back & pull-ups"),
              exerciseIDs: ["Pullups", "Chin-Up", "Band_Assisted_Pull-Up", "Inverted_Row", "Bent_Over_Barbell_Row", "Barbell_Shrug"]),
        Group(id: "core", title: Localized(bg: "Корем", en: "Core"),
              exerciseIDs: ["Hanging_Leg_Raise", "Landmine_180s"]),
    ]
}
