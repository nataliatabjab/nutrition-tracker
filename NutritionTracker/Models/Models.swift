import Foundation
import SwiftData

/// An alternative way to measure a food, e.g. "1 cup" = 240 g.
struct Portion: Codable, Hashable {
    var label: String
    var grams: Double
}

/// One line of a recipe, with the nutrients for the amount used.
struct Ingredient: Codable, Hashable {
    var name: String
    var amountText: String
    /// Weight of the amount used; 0 when unknown.
    var grams: Double
    var nutrients: NutrientValues
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// A saved food. Nutrients are stored for one serving (`servingLabel`).
@Model
final class Food {
    var name: String
    var brand: String
    var servingLabel: String
    /// Weight of one serving in grams; 0 when unknown (the food can then only be logged by serving).
    var servingGrams: Double
    var nutrientData: Data
    var portionData: Data
    var createdAt: Date
    /// Recipes only. Defaults keep foods saved by earlier versions readable.
    var ingredientData: Data = Data()
    var recipeServings: Double = 0

    init(name: String, brand: String = "", servingLabel: String, servingGrams: Double,
         nutrients: NutrientValues, portions: [Portion] = []) {
        self.name = name
        self.brand = brand
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.nutrientData = (try? JSONEncoder().encode(nutrients)) ?? Data()
        self.portionData = (try? JSONEncoder().encode(portions)) ?? Data()
        self.createdAt = Date()
    }

    var nutrients: NutrientValues {
        get { (try? JSONDecoder().decode(NutrientValues.self, from: nutrientData)) ?? [:] }
        set { nutrientData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var portions: [Portion] {
        get { (try? JSONDecoder().decode([Portion].self, from: portionData)) ?? [] }
        set { portionData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var ingredients: [Ingredient] {
        get { (try? JSONDecoder().decode([Ingredient].self, from: ingredientData)) ?? [] }
        set { ingredientData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var isRecipe: Bool { recipeServings > 0 }
}

/// One logged item. It keeps its own copy of the nutrients so editing a food later doesn't rewrite history.
@Model
final class LogEntry {
    var date: Date
    var meal: String
    var foodName: String
    var amountText: String
    var nutrientData: Data

    init(date: Date, meal: Meal, foodName: String, amountText: String, nutrients: NutrientValues) {
        self.date = date
        self.meal = meal.rawValue
        self.foodName = foodName
        self.amountText = amountText
        self.nutrientData = (try? JSONEncoder().encode(nutrients)) ?? Data()
    }

    var nutrients: NutrientValues {
        (try? JSONDecoder().decode(NutrientValues.self, from: nutrientData)) ?? [:]
    }
}

/// A food ready to be logged, whether it came from My Foods or a USDA search.
struct FoodDraft {
    var name: String
    var brand: String
    var servingLabel: String
    var servingGrams: Double
    var nutrients: NutrientValues
    var portions: [Portion]
    /// Set when the draft comes from My Foods, so it isn't saved a second time.
    var isSaved: Bool

    init(food: Food) {
        name = food.name
        brand = food.brand
        servingLabel = food.servingLabel
        servingGrams = food.servingGrams
        nutrients = food.nutrients
        portions = food.portions
        isSaved = true
    }

    init(name: String, brand: String, servingLabel: String, servingGrams: Double,
         nutrients: NutrientValues, portions: [Portion]) {
        self.name = name
        self.brand = brand
        self.servingLabel = servingLabel
        self.servingGrams = servingGrams
        self.nutrients = nutrients
        self.portions = portions
        isSaved = false
    }
}
