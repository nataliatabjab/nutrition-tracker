import Foundation

/// Every nutrient the app tracks. Raw values are the keys used in stored nutrient dictionaries.
enum Nutrient: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat
    case fiber, addedSugar, sodium
    case vitaminD, selenium, iron, zinc, iodine, magnesium, vitaminB12, calcium, omega3

    var id: String { rawValue }

    static let macros: [Nutrient] = [.protein, .carbs, .fat]
    static let micros: [Nutrient] = [
        .fiber, .addedSugar, .sodium, .vitaminD, .selenium, .iron, .zinc,
        .iodine, .magnesium, .vitaminB12, .calcium, .omega3,
    ]

    var name: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .fiber: return "Fiber"
        case .addedSugar: return "Added sugar"
        case .sodium: return "Sodium"
        case .vitaminD: return "Vitamin D"
        case .selenium: return "Selenium"
        case .iron: return "Iron"
        case .zinc: return "Zinc"
        case .iodine: return "Iodine"
        case .magnesium: return "Magnesium"
        case .vitaminB12: return "Vitamin B12"
        case .calcium: return "Calcium"
        case .omega3: return "Omega-3"
        }
    }

    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .protein, .carbs, .fat, .fiber, .addedSugar, .omega3: return "g"
        case .sodium, .iron, .zinc, .magnesium, .calcium: return "mg"
        case .vitaminD, .selenium, .iodine, .vitaminB12: return "mcg"
        }
    }

    /// Starting targets (general adult-woman reference values). Editable in Settings.
    var defaultTarget: Double {
        switch self {
        case .calories: return 2000
        case .protein: return 100
        case .carbs: return 225
        case .fat: return 70
        case .fiber: return 25
        case .addedSugar: return 25
        case .sodium: return 2300
        case .vitaminD: return 15
        case .selenium: return 55
        case .iron: return 18
        case .zinc: return 8
        case .iodine: return 150
        case .magnesium: return 320
        case .vitaminB12: return 2.4
        case .calcium: return 1000
        case .omega3: return 1.1
        }
    }

    /// True when the target is a ceiling to stay under rather than a goal to reach.
    var isLimit: Bool {
        self == .addedSugar || self == .sodium
    }

    /// Tolerable upper intake level, where one applies to food intake.
    var upperLimit: Double? {
        switch self {
        case .vitaminD: return 100
        case .selenium: return 400
        case .iron: return 45
        case .zinc: return 40
        case .iodine: return 1100
        case .calcium: return 2500
        default: return nil
        }
    }

    /// USDA FoodData Central nutrient numbers, in order of preference.
    var usdaNumbers: [String] {
        switch self {
        case .calories: return ["208", "958", "957"]
        case .protein: return ["203"]
        case .carbs: return ["205"]
        case .fat: return ["204"]
        case .fiber: return ["291"]
        case .addedSugar: return ["539"]
        case .sodium: return ["307"]
        case .vitaminD: return ["328"]
        case .selenium: return ["317"]
        case .iron: return ["303"]
        case .zinc: return ["309"]
        case .iodine: return ["314"]
        case .magnesium: return ["304"]
        case .vitaminB12: return ["418"]
        case .calcium: return ["301"]
        case .omega3: return ["851", "629", "621"] // ALA + EPA + DHA
        }
    }

    /// Omega-3 is the sum of its USDA numbers; everything else uses the first one present.
    var sumsUSDANumbers: Bool { self == .omega3 }
}

typealias NutrientValues = [String: Double]

extension Dictionary where Key == String, Value == Double {
    subscript(_ nutrient: Nutrient) -> Double {
        get { self[nutrient.rawValue] ?? 0 }
        set { self[nutrient.rawValue] = newValue }
    }

    func scaled(by factor: Double) -> NutrientValues {
        mapValues { $0 * factor }
    }

    func adding(_ other: NutrientValues) -> NutrientValues {
        merging(other) { $0 + $1 }
    }
}

func formatAmount(_ value: Double) -> String {
    if value >= 100 || value == value.rounded() {
        return String(format: "%.0f", value)
    }
    return String(format: value < 10 ? "%.1f" : "%.0f", value)
}
