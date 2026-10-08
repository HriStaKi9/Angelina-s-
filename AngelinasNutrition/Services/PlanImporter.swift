import Foundation

/// Turns an eating-plan PDF into a `PersonalPlan` using Claude (the user's own API key).
/// Claude reads the PDF directly and answers in a fixed JSON schema (structured outputs).
enum PlanImporter {
    enum Target: Hashable {
        /// A new person with this name.
        case newPerson(String)
        /// Replace the eating plan of an existing person, keeping their training program.
        case replaceNutrition(String)
    }

    enum ImportError: LocalizedError {
        case refused, truncated, invalidJSON(String), empty

        var errorDescription: String? {
            switch self {
            case .refused: "Claude declined to read this PDF."
            case .truncated: "The plan was too long to finish in one go."
            case .invalidJSON(let detail): "Couldn't read Claude's answer: \(detail)"
            case .empty: "No meals were found in this PDF."
            }
        }
    }

    // MARK: Request

    static func requestBody(pdf: Data) -> [String: Any] {
        let catalog = GroceryCatalog.shared.items.values.sorted { $0.key < $1.key }
        let catalogList = catalog.map { "\($0.key) = \($0.name.bg) / \($0.name.en)" }.joined(separator: "\n")
        let prompt = """
        This PDF is a personal eating plan. Convert it into the JSON schema, keeping everything it contains: targets, every meal option for breakfast, lunch, dinner and snacks (with ingredients, preparation, kcal and protein), the sample week, rules and notes, and any "what you see → what to do" adjustment table.

        Give every text in both Bulgarian (bg) and English (en): keep the PDF's own wording in its language and translate it to the other. Don't invent content. Where the PDF gives a single number, use it for both low and high; where it gives none, estimate from the ingredients. Number meal options the way the PDF does. If there is no sample week, return an empty week. Body stats: use 0 (and sex "unknown") when the PDF doesn't say.

        For each ingredient line with an amount, add `shop` entries mapping it to these grocery items (qty in g, ml or pcs; eggs are pcs; split mixed lines like "300 g vegetables – courgettes, carrots, peppers" across the named items). Lines without an amount (spices, "to taste") get an empty `shop`.
        \(catalogList)
        """
        return [
            "max_tokens": 64000,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": pdf.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": schema(catalogKeys: catalog.map(\.key))],
            ],
        ]
    }

    /// JSON schema for the answer. Structured outputs need `additionalProperties: false` on every object
    /// and support no length/number limits, so ranges are low/high pairs.
    static func schema(catalogKeys: [String]) -> [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
        }
        func array(_ items: Any) -> [String: Any] { ["type": "array", "items": items] }
        let text = ["$ref": "#/$defs/text"]
        let int = ["type": "integer"]
        let shop = object([
            "item": ["type": "string", "enum": catalogKeys],
            "qty": ["type": "number"],
            "unit": ["type": "string", "enum": ["g", "ml", "pcs"]],
        ])
        let meal = object([
            "course": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]],
            "number": int,
            "name": text,
            "ingredients": array(object(["bg": ["type": "string"], "en": ["type": "string"], "shop": array(shop)])),
            "steps": text,
            "kcalLow": int, "kcalHigh": int, "proteinLow": int, "proteinHigh": int,
        ])
        let day = object(["weekday": int, "breakfast": int, "lunch": int, "dinner": int, "snacks": array(int)])
        let section = object(["title": text, "items": array(text), "style": ["type": "string", "enum": ["list", "warning", "info"]]])
        var root = object([
            "personName": text,
            "body": object([
                "sex": ["type": "string", "enum": ["female", "male", "unknown"]],
                "weight": ["type": "number"], "height": ["type": "number"], "age": int,
                "breastfeeding": ["type": "boolean"],
            ]),
            "title": text, "goal": text, "stats": text,
            "kcalLow": int, "kcalHigh": int, "proteinLow": int, "proteinHigh": int,
            "mealsPerDay": text, "pace": text, "aboutTitle": text, "about": array(text),
            "weekNote": text, "dayFlow": array(text),
            "meals": array(meal), "week": array(day), "sections": array(section),
            "adjustments": array(object(["when": text, "action": text])),
            "important": text,
        ])
        root["$defs"] = ["text": object(["bg": ["type": "string"], "en": ["type": "string"]])]
        return root
    }

    // MARK: Response

    struct DTO: Decodable {
        struct Shop: Decodable { let item: String; let qty: Double; let unit: ShopAmount.Unit }
        struct Ingredient: Decodable { let bg: String; let en: String; let shop: [Shop] }
        struct MealDTO: Decodable {
            let course: Meal.Course; let number: Int; let name: Localized
            let ingredients: [Ingredient]; let steps: Localized
            let kcalLow: Int; let kcalHigh: Int; let proteinLow: Int; let proteinHigh: Int
        }
        struct Body: Decodable { let sex: String; let weight: Double; let height: Double; let age: Int; let breastfeeding: Bool }
        struct Section: Decodable { let title: Localized; let items: [Localized]; let style: InfoSection.Style }
        struct Adjustment: Decodable { let when: Localized; let action: Localized }

        let personName: Localized
        let body: Body
        let title: Localized, goal: Localized, stats: Localized
        let kcalLow: Int, kcalHigh: Int, proteinLow: Int, proteinHigh: Int
        let mealsPerDay: Localized, pace: Localized, aboutTitle: Localized
        let about: [Localized], weekNote: Localized, dayFlow: [Localized]
        let meals: [MealDTO], week: [DayMenu], sections: [Section], adjustments: [Adjustment]
        let important: Localized
    }

    static func parse(_ json: String) throws -> DTO {
        do {
            return try JSONDecoder().decode(DTO.self, from: Data(json.utf8))
        } catch {
            throw ImportError.invalidJSON(String(describing: error).prefix(200).description)
        }
    }

    static func makeNutrition(_ dto: DTO) throws -> NutritionPlan {
        func range(_ low: Int, _ high: Int) -> ApproxRange { ApproxRange(min(low, high), max(low, high)) }
        func nonEmpty(_ l: Localized) -> Localized? { l.bg.isEmpty && l.en.isEmpty ? nil : l }

        let meals = dto.meals.map { m in
            Meal(course: m.course, number: m.number, name: m.name,
                 ingredients: m.ingredients.map { i in
                     Ingredient(bg: i.bg, en: i.en,
                                shop: i.shop.isEmpty ? nil : i.shop.map { ShopAmount(item: $0.item, qty: $0.qty, unit: $0.unit) })
                 },
                 steps: nonEmpty(m.steps), kcal: range(m.kcalLow, m.kcalHigh), protein: range(m.proteinLow, m.proteinHigh))
        }
        guard !meals.isEmpty else { throw ImportError.empty }

        let numbers = { (course: Meal.Course) in meals.filter { $0.course == course }.map(\.number).sorted() }
        var week = dto.week.filter { (1...7).contains($0.weekday) }
        if week.isEmpty {
            // No sample week in the PDF: rotate through the options so every day has a menu.
            let b = numbers(.breakfast), l = numbers(.lunch), d = numbers(.dinner), s = numbers(.snack)
            week = (1...7).map { day in
                func pick(_ list: [Int]) -> Int { list.isEmpty ? 0 : list[(day - 1) % list.count] }
                return DayMenu(weekday: day, breakfast: pick(b), lunch: pick(l), dinner: pick(d),
                               snacks: s.isEmpty ? [] : [pick(s)])
            }
        }

        return NutritionPlan(
            title: dto.title, goal: dto.goal, stats: dto.stats,
            kcal: range(dto.kcalLow, dto.kcalHigh), protein: range(dto.proteinLow, dto.proteinHigh),
            mealsPerDay: dto.mealsPerDay, pace: dto.pace, aboutTitle: dto.aboutTitle, about: dto.about,
            meals: meals, week: week, weekNote: nonEmpty(dto.weekNote),
            dayFlow: dto.dayFlow.isEmpty ? nil : dto.dayFlow,
            sections: dto.sections.map { InfoSection(title: $0.title, items: $0.items, style: $0.style) },
            adjustments: dto.adjustments.isEmpty ? nil : AdjustmentTable(
                title: Localized(bg: "Корекции", en: "Adjustments"),
                rows: dto.adjustments.map { AdjustmentTable.Row(when: $0.when, action: $0.action, trigger: nil) }),
            important: nonEmpty(dto.important)
        )
    }

    /// Builds the plan to save: a new person, or an existing person with their eating plan replaced.
    static func makePlan(_ dto: DTO, target: Target, library: PlanLibrary = .shared) throws -> PersonalPlan {
        let nutrition = try makeNutrition(dto)
        let body: BodyStats? = dto.body.weight > 0 && dto.body.height > 0 && dto.body.age > 0 && dto.body.sex != "unknown"
            ? BodyStats(sex: dto.body.sex == "male" ? .male : .female, weight: dto.body.weight, height: dto.body.height,
                        age: dto.body.age, activity: 1.375, weeklyChange: 0, breastfeeding: dto.body.breastfeeding)
            : nil

        switch target {
        case .replaceNutrition(let id):
            guard let existing = library.plan(id: id) else { throw ImportError.empty }
            return PersonalPlan(id: existing.id, name: existing.name, accent: existing.accent, nutrition: nutrition,
                                training: existing.training, checkIn: existing.checkIn, adviceSource: existing.adviceSource,
                                body: body ?? existing.body)
        case .newPerson(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let display = trimmed.isEmpty ? dto.personName : Localized(bg: trimmed, en: trimmed)
            return PersonalPlan(id: "imported-\(UUID().uuidString.prefix(8).lowercased())", name: display,
                                accent: "berry", nutrition: nutrition, training: .empty,
                                checkIn: CheckInSpec(fields: [.weight, .waist], flags: [.fatigue, .hunger]),
                                adviceSource: "nutrition", body: body)
        }
    }
}

extension TrainingProgram {
    /// Placeholder for people imported from an eating-plan PDF without a training program.
    static let empty = TrainingProgram(
        title: Localized(bg: "Няма тренировъчна програма", en: "No training program"),
        subtitle: Localized(bg: "Този план е само хранителен режим", en: "This plan only has an eating plan"),
        stats: Localized(bg: "Разгледай „Още упражнения“ за идеи", en: "Browse “More exercises” for ideas"),
        schedule: [], scheduleNote: nil, warmUp: [], callouts: [], workouts: [], sections: [],
        adjustments: nil, shortVersion: nil, deloadEvery: nil, extraExercises: nil)
}
