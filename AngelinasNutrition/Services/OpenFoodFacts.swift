import Foundation

/// Open Food Facts: free, open product database (no key). Search via search.openfoodfacts.org,
/// barcodes via the product API.
enum OpenFoodFacts {
    private static let userAgent = "AngelinasNutrition/0.1 (iOS app)"
    private static let fields = "code,product_name,product_name_bg,brands,nutriments,serving_quantity"

    static func search(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: fields),
        ]
        let json = try await fetch(components.url!)
        return (json["hits"] as? [[String: Any]] ?? []).compactMap(item)
    }

    static func product(barcode: String) async throws -> FoodItem? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=\(fields)")!
        let json = try await fetch(url)
        guard (json["status"] as? Int) == 1, var product = json["product"] as? [String: Any] else { return nil }
        product["code"] = product["code"] ?? barcode
        return item(product)
    }

    private static func fetch(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }

    /// Maps a product to a FoodItem; products without calories are skipped.
    static func item(_ p: [String: Any]) -> FoodItem? {
        guard let code = p["code"] as? String, let n = p["nutriments"] as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Double(s) }
            return nil
        }
        guard let kcal = number("energy-kcal_100g") ?? number("energy_100g").map({ $0 / 4.184 }) else { return nil }
        let name = (p["product_name_bg"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (p["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? code
        let brand: String? = (p["brands"] as? [String])?.first?.trimmingCharacters(in: .whitespaces)
            ?? (p["brands"] as? String)?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = (p["serving_quantity"] as? Double) ?? (p["serving_quantity"] as? String).flatMap(Double.init)
        return FoodItem(id: "off:\(code)", name: Localized(bg: name, en: name), brand: brand,
                        per100: Nutrients(kcal: kcal, protein: number("proteins_100g") ?? 0,
                                          carbs: number("carbohydrates_100g"), fat: number("fat_100g")),
                        portion: serving.flatMap { $0 > 0 ? $0 : nil })
    }
}
