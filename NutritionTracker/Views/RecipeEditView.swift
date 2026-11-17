import SwiftUI
import SwiftData

/// Build a recipe from ingredients (pass nil), or edit a saved one.
/// The recipe is saved as a food whose serving is one portion of the finished dish.
struct RecipeEditView: View {
    let recipe: Food?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var servings: Double?
    @State private var ingredients: [Ingredient]
    @State private var category: String
    @State private var photoData: Data?
    @State private var addingIngredient = false

    init(recipe: Food?) {
        self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.recipeServings ?? 1)
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
        _category = State(initialValue: recipe?.category ?? "")
        _photoData = State(initialValue: recipe?.photoData)
    }

    private var servingCount: Double {
        max(servings ?? 0, 0)
    }

    private var total: NutrientValues {
        ingredients.reduce(into: [:]) { $0 = $0.adding($1.nutrients) }
    }

    private var perServing: NutrientValues {
        servingCount > 0 ? total.scaled(by: 1 / servingCount) : [:]
    }

    /// Weight of one serving, known only when every ingredient has a weight.
    private var servingGrams: Double {
        guard servingCount > 0, !ingredients.isEmpty, ingredients.allSatisfy({ $0.grams > 0 }) else { return 0 }
        return ingredients.reduce(0) { $0 + $1.grams } / servingCount
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servingCount > 0 && !ingredients.isEmpty
    }

    var body: some View {
        if recipe == nil {
            NavigationStack { form }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                PhotoField(photoData: $photoData)
            }
            Section("Recipe") {
                TextField("Name (e.g. Overnight oats)", text: $name)
                CategoryPicker(category: $category, recipe: true)
                HStack {
                    Text("Servings it makes")
                    Spacer()
                    TextField("1", value: $servings, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Ingredients") {
                if ingredients.isEmpty {
                    EmptyIllustration(symbol: "carrot.fill", title: "No ingredients yet",
                                      message: "Add each ingredient with the amount that goes into the whole recipe.")
                }
                ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ingredient.name)
                            Text(ingredient.amountText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(formatAmount(ingredient.nutrients[.calories])) kcal")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                Button {
                    addingIngredient = true
                } label: {
                    Label("Add ingredient", systemImage: "plus.circle.fill")
                }
            }

            if !ingredients.isEmpty && servingCount > 0 {
                Section("Per serving") {
                    ForEach(Nutrient.allCases) { nutrient in
                        if total[nutrient.rawValue] != nil {
                            HStack(spacing: 12) {
                                IconBadge(symbol: nutrient.symbol, color: nutrient.color, size: 26)
                                Text(nutrient.name)
                                Spacer()
                                Text("\(formatAmount(perServing[nutrient])) \(nutrient.unit)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recipe == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $addingIngredient) {
            AddFoodView(onIngredient: { ingredients.append($0) })
        }
    }

    private func save() {
        let food = recipe ?? Food(name: name, servingLabel: "1 serving", servingGrams: 0, nutrients: [:])
        food.name = name
        food.servingGrams = servingGrams
        food.nutrients = perServing
        food.ingredients = ingredients
        food.recipeServings = servingCount
        food.category = category
        food.photoData = photoData
        if recipe == nil {
            context.insert(food)
        }
        dismiss()
    }
}
