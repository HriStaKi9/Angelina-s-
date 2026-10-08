import Foundation

/// Plain-text renderings of a plan: the one-page summaries (shareable) and Claude's context.
enum PlanSummary {
    // MARK: Nutrition

    static func nutrition(_ plan: PersonalPlan, week: [DayMenu], language lang: ContentLanguage, includeSteps: Bool = false) -> String {
        let n = plan.nutrition
        let bg = lang == .bg
        var out: [String] = []
        out.append("\(n.title[lang].uppercased()) – \(plan.name[lang])")
        out.append(n.goal[lang])
        out.append(n.stats[lang])
        out.append("\(bg ? "Калории" : "Calories"): \(n.kcal.text) kcal · \(bg ? "Протеин" : "Protein"): \(n.protein.text) \(bg ? "г" : "g") · \(n.mealsPerDay[lang]) · \(n.pace[lang])")
        out.append("")
        out.append(n.aboutTitle[lang].uppercased())
        out += n.about.map { "• \($0[lang])" }
        if let flow = n.dayFlow { out += flow.map { "• \($0[lang])" } }

        out.append("")
        out.append((bg ? "СЕДМИЧНО МЕНЮ" : "WEEKLY MENU"))
        for day in week.sorted(by: { $0.weekday < $1.weekday }) {
            let totals = day.totals(in: n)
            let names = day.meals(in: n).map { "\($0.course.title[lang]) №\($0.number) \($0.name[lang])" }
            out.append("\(weekdayName(day.weekday, lang)): \(names.joined(separator: "; ")) (≈ \(totals.kcal.text) kcal, \(totals.protein.text) \(bg ? "г протеин" : "g protein"))")
        }

        for course in Meal.Course.allCases {
            out.append("")
            out.append(course.pluralTitle[lang].uppercased())
            for meal in n.meals(for: course) {
                out.append("№\(meal.number) \(meal.name[lang]) – ≈ \(meal.kcal.text) kcal, \(meal.protein.text) \(bg ? "г протеин" : "g protein")")
                out.append("   \(meal.ingredients.map { $0[lang] }.joined(separator: ", "))")
                if includeSteps, let steps = meal.steps { out.append("   \(steps[lang])") }
            }
        }

        for section in n.sections {
            out.append("")
            out.append(section.title[lang].uppercased())
            out += section.items.map { "• \($0[lang])" }
        }
        if let table = n.adjustments { out += adjustmentLines(table, lang) }
        if let important = n.important {
            out.append("")
            out.append("\(bg ? "ВАЖНО" : "IMPORTANT"): \(important[lang])")
        }
        return out.joined(separator: "\n")
    }

    // MARK: Training

    static func training(_ plan: PersonalPlan, language lang: ContentLanguage) -> String {
        let t = plan.training
        let bg = lang == .bg
        var out: [String] = []
        out.append("\(t.title[lang].uppercased()) – \(plan.name[lang])")
        out.append(t.subtitle[lang])
        out.append(t.stats[lang])
        out.append("")
        out.append(bg ? "СЕДМИЧЕН ГРАФИК" : "WEEKLY SCHEDULE")
        for (index, week) in t.schedule.enumerated() {
            let days = week.enumerated().map { offset, day in
                "\(weekdayName(offset + 1, lang)) \(day.workout.flatMap(t.workout(id:))?.short[lang] ?? day.kindTitle[lang])"
            }
            out.append((t.schedule.count > 1 ? "\(bg ? "Седм." : "Week") \(index + 1): " : "") + days.joined(separator: " · "))
        }
        if let note = t.scheduleNote { out.append(note[lang]) }
        out.append("")
        out.append(bg ? "ЗАГРЯВКА" : "WARM-UP")
        out += t.warmUp.map { "• \($0[lang])" }
        for callout in t.callouts {
            out.append("")
            out.append(callout.title[lang].uppercased())
            out += callout.items.map { "• \($0[lang])" }
        }
        for workout in t.workouts {
            out.append("")
            out.append([workout.title[lang], workout.duration[lang], workout.focus?[lang]].compactMap { $0 }.joined(separator: " · ").uppercased())
            for item in workout.exercises {
                var line = "\(item.label). \(item.name[lang]) – \(item.prescription[lang]), \(bg ? "почивка" : "rest") \(item.rest[lang])"
                if let start = item.start { line += ", \(bg ? "старт" : "start") \(start[lang])" }
                out.append(line)
                out += item.cues.map { "   – \($0[lang])" }
                if !item.alternatives.isEmpty {
                    out.append("   \(bg ? "Алтернативи" : "Alternatives"): " + item.alternatives.map { "\($0.name[lang]) (\($0.place.title[lang]))" }.joined(separator: ", "))
                }
            }
            if let finisher = workout.finisher { out.append(finisher[lang]) }
        }
        if let short = t.shortVersion {
            out.append("")
            out.append(short.note[lang])
        }
        for section in t.sections {
            out.append("")
            out.append(section.title[lang].uppercased())
            out += section.items.map { "• \($0[lang])" }
        }
        if let table = t.adjustments { out += adjustmentLines(table, lang) }
        return out.joined(separator: "\n")
    }

    // MARK: Claude context

    /// Live data that changes between messages: date, today's session, check-ins and recent workouts.
    static func todayContext(plan: PersonalPlan?, store: ProfileStore, log: TrainingLog, menus: WeekMenuStore, now: Date = .now) -> String {
        var out: [String] = []
        out.append("Today: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "en_GB"))))")
        guard let plan else {
            out.append("No personal plan selected. Goal: \(store.profile.goal.title); trains at \(store.profile.location.title.lowercased()); level \(store.profile.level.title).")
            return out.joined(separator: "\n")
        }
        if let today = store.programDay(on: now) {
            let session = today.workout.map { "\($0.title.en) (\($0.title.bg))" } ?? today.day.kindTitle.en
            out.append("Program week \(today.week). Today's session: \(session).")
        }
        if let menu = menus.menu(for: plan, weekday: TrainingProgram.mondayBasedWeekday(of: now)) {
            let names = menu.meals(in: plan.nutrition).map { "\($0.course.title.en) #\($0.number) \($0.name.bg)" }
            out.append("Today's chosen menu: \(names.joined(separator: "; ")).")
        }
        out.append("")
        out.append("User's chosen week menu (may differ from the sample week):")
        for day in menus.week(for: plan) {
            out.append("- \(weekdayName(day.weekday, .en)): breakfast #\(day.breakfast), lunch #\(day.lunch), dinner #\(day.dinner), snacks \(day.snacks.map { "#\($0)" }.joined(separator: ", "))")
        }

        let checkIns = log.checkIns(planID: plan.id).filter { now.timeIntervalSince($0.date) < 28 * 86_400 }
        if !checkIns.isEmpty {
            out.append("")
            out.append("Check-ins (last 4 weeks, newest first):")
            for item in checkIns {
                var parts: [String] = []
                if let w = item.weight { parts.append("weight \(w.trimmed) kg") }
                if let w = item.waist { parts.append("waist \(w.trimmed) cm") }
                if let h = item.hips { parts.append("hips \(h.trimmed) cm") }
                if let s = item.steps { parts.append("steps \(s)") }
                parts += item.flags.map { $0.title.en.lowercased() }
                out.append("- \(item.date.formatted(.iso8601.year().month().day())): \(parts.joined(separator: ", "))")
            }
            let advice = PlanAdvisor.advice(table: plan.adviceTable, checkIns: log.checkIns(planID: plan.id),
                                            programStart: store.programStart, currentWeek: store.programDay(on: now)?.week ?? 1, now: now)
            if let change = advice.weeklyChange { out.append("Weekly average weight change: \(change.formatted(.number.precision(.fractionLength(1)))) kg.") }
            if case .matched(let row) = advice.status {
                out.append("The plan's adjustment table currently matches: \"\(row.when.en)\" → \"\(row.action.en)\".")
            }
        }

        let workouts = log.workouts(planID: plan.id).prefix(6)
        if !workouts.isEmpty {
            out.append("")
            out.append("Recent workouts (newest first, weight × reps per set):")
            for session in workouts {
                let title = (store.trainingPlan ?? plan).training.workout(id: session.workoutID)?.title.en ?? session.workoutID
                out.append("- \(session.date.formatted(.iso8601.year().month().day())) \(title), week \(session.week)\(session.isShort ? ", short version" : "")\(session.isDeload ? ", deload" : "")")
                for exercise in session.exercises {
                    let sets = exercise.doneSets.map { set -> String in
                        if let s = set.seconds { return "\(s)s" }
                        return set.weight.map { "\($0.trimmed)×\(set.reps ?? 0)" } ?? "×\(set.reps ?? 0)"
                    }
                    out.append("  \(exercise.slot). \(exercise.name.en): \(sets.joined(separator: ", "))\(exercise.feltEasy ? " (felt easy)" : "")")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    static func weekdayName(_ weekday: Int, _ lang: ContentLanguage) -> String {
        let bg = ["Понеделник", "Вторник", "Сряда", "Четвъртък", "Петък", "Събота", "Неделя"]
        let en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return (lang == .bg ? bg : en)[max(0, min(6, weekday - 1))]
    }

    static func shortWeekday(_ weekday: Int, _ lang: ContentLanguage) -> String {
        let bg = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд"]
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return (lang == .bg ? bg : en)[max(0, min(6, weekday - 1))]
    }

    private static func adjustmentLines(_ table: AdjustmentTable, _ lang: ContentLanguage) -> [String] {
        ["", table.title[lang].uppercased()] + table.rows.map { "• \($0.when[lang]) → \($0.action[lang])" }
    }
}
