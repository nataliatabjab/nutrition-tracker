import Foundation

/// Food search against USDA FoodData Central (https://fdc.nal.usda.gov/api-guide).
enum USDAService {
    /// Works without signing up, but is limited to a handful of searches per hour.
    static let demoKey = "DEMO_KEY"

    enum SearchError: LocalizedError {
        case rateLimited
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "USDA search limit reached. Add your own free API key in Settings."
            case .badResponse(let code):
                return "USDA search failed (error \(code))."
            }
        }
    }

    static func search(_ query: String, apiKey: String) async throws -> [FoodDraft] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey.isEmpty ? demoKey : apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "30"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? SearchError.rateLimited : SearchError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).foods.map(\.draft)
    }

    private struct SearchResponse: Decodable {
        let foods: [Item]
    }

    private struct Item: Decodable {
        let description: String
        let brandOwner: String?
        let brandName: String?
        let servingSize: Double?
        let servingSizeUnit: String?
        let householdServingFullText: String?
        let foodNutrients: [FoodNutrient]?
        let foodMeasures: [FoodMeasure]?

        /// USDA reports nutrients per 100 g, so that is the draft's base serving.
        var draft: FoodDraft {
            var amounts: [String: Double] = [:]
            for item in foodNutrients ?? [] {
                guard let number = item.nutrientNumber, let value = item.value else { continue }
                if number == "208", item.unitName?.uppercased() != "KCAL" { continue }
                amounts[number] = value
            }
            var per100g: NutrientValues = [:]
            for nutrient in Nutrient.allCases {
                let found = nutrient.usdaNumbers.compactMap { amounts[$0] }
                guard !found.isEmpty else { continue }
                per100g[nutrient] = nutrient.sumsUSDANumbers ? found.reduce(0, +) : found[0]
            }

            var portions: [Portion] = []
            let unit = servingSizeUnit?.lowercased() ?? ""
            if let size = servingSize, size > 0, ["g", "grm", "ml", "mlt"].contains(unit) {
                let label = householdServingFullText?.isEmpty == false ? householdServingFullText! : "1 serving"
                portions.append(Portion(label: label, grams: size))
            }
            for measure in foodMeasures ?? [] {
                guard let label = measure.disseminationText, let grams = measure.gramWeight,
                      grams > 0, label != "Quantity not specified" else { continue }
                portions.append(Portion(label: label, grams: grams))
            }

            return FoodDraft(
                name: description.capitalized,
                brand: brandName ?? brandOwner ?? "",
                servingLabel: "100 g",
                servingGrams: 100,
                nutrients: per100g,
                portions: portions
            )
        }
    }

    private struct FoodNutrient: Decodable {
        let nutrientNumber: String?
        let unitName: String?
        let value: Double?
    }

    private struct FoodMeasure: Decodable {
        let disseminationText: String?
        let gramWeight: Double?
    }
}
