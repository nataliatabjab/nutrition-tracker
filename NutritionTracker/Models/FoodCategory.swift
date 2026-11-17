import Foundation

/// Categories for browsing My Foods. Stored on `Food.category` by raw value; "" means uncategorized.
enum FoodCategory: String, CaseIterable, Identifiable {
    case fruit, vegetables, meatFish, eggsDairy, grains, legumes, nutsSeeds, fatsOils
    case drinks, snacksSweets, breakfast, meals, salads, desserts, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fruit: return "Fruit"
        case .vegetables: return "Vegetables"
        case .meatFish: return "Meat & fish"
        case .eggsDairy: return "Eggs & dairy"
        case .grains: return "Grains & bread"
        case .legumes: return "Beans & lentils"
        case .nutsSeeds: return "Nuts & seeds"
        case .fatsOils: return "Fats & oils"
        case .drinks: return "Drinks"
        case .snacksSweets: return "Snacks & sweets"
        case .breakfast: return "Breakfast"
        case .meals: return "Meals"
        case .salads: return "Salads"
        case .desserts: return "Desserts"
        case .other: return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .fruit: return "🍎"
        case .vegetables: return "🥦"
        case .meatFish: return "🍗"
        case .eggsDairy: return "🥚"
        case .grains: return "🌾"
        case .legumes: return "🫘"
        case .nutsSeeds: return "🥜"
        case .fatsOils: return "🫒"
        case .drinks: return "🥤"
        case .snacksSweets: return "🍫"
        case .breakfast: return "🍳"
        case .meals: return "🍲"
        case .salads: return "🥗"
        case .desserts: return "🍰"
        case .other: return "🍽️"
        }
    }

    /// Best guess from a USDA category name, e.g. "Fruits and Fruit Juices" or "Cheese".
    static func guess(fromUSDA usdaCategory: String) -> FoodCategory? {
        let text = usdaCategory.lowercased()
        let rules: [(FoodCategory, [String])] = [
            (.fruit, ["fruit"]),
            (.vegetables, ["vegetable", "salad greens", "potato"]),
            (.legumes, ["legume", "bean", "lentil", "tofu", "soy"]),
            (.nutsSeeds, ["nut", "seed"]),
            (.eggsDairy, ["egg", "dairy", "milk", "cheese", "yogurt"]),
            (.meatFish, ["beef", "pork", "poultry", "chicken", "turkey", "lamb", "sausage", "meat",
                         "finfish", "shellfish", "fish", "seafood"]),
            (.fatsOils, ["fats", "oil", "butter"]),
            (.drinks, ["beverage", "juice", "coffee", "tea", "water", "soda"]),
            (.breakfast, ["cereal", "breakfast"]),
            (.grains, ["grain", "pasta", "bread", "baked", "rice", "flour", "cracker", "tortilla"]),
            (.desserts, ["dessert", "ice cream", "cake", "cookie", "pastr"]),
            (.snacksSweets, ["snack", "sweet", "candy", "chocolate", "chip"]),
            (.meals, ["meal", "entree", "soup", "sandwich", "pizza", "fast food", "restaurant", "mixed dish"]),
        ]
        return rules.first { _, words in words.contains { text.contains($0) } }?.0
    }
}
