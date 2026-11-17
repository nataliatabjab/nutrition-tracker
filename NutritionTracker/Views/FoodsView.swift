import SwiftUI
import SwiftData

/// The saved-foods library: browse, edit, delete and create foods.
struct FoodsView: View {
    @Query(sort: \Food.name) private var foods: [Food]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var creatingFood = false
    @State private var creatingRecipe = false

    var body: some View {
        NavigationStack {
            List {
                if foods.isEmpty {
                    EmptyIllustration(symbol: "fork.knife", title: "No saved foods yet",
                                      message: "Foods you create or log from the USDA database are saved here.")
                }
                ForEach(foods.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { food in
                    NavigationLink {
                        if food.isRecipe {
                            RecipeEditView(recipe: food)
                        } else {
                            FoodEditView(food: food)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: food.isRecipe ? "book.fill" : "fork.knife",
                                      color: food.isRecipe ? .orange : .accentColor)
                            VStack(alignment: .leading) {
                                Text(food.name)
                                Text("\(formatAmount(food.nutrients[.calories])) kcal per \(food.servingLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(food) }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("My Foods")
            .toolbar {
                Menu {
                    Button { creatingFood = true } label: { Label("New food", systemImage: "fork.knife") }
                    Button { creatingRecipe = true } label: { Label("New recipe", systemImage: "book.fill") }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $creatingFood) {
                FoodEditView(food: nil)
            }
            .sheet(isPresented: $creatingRecipe) {
                RecipeEditView(recipe: nil)
            }
        }
    }
}

/// Create a food by hand (pass nil), or edit a saved one.
struct FoodEditView: View {
    let food: Food?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var brand: String
    @State private var servingLabel: String
    @State private var servingGrams: Double?
    @State private var values: NutrientValues

    init(food: Food?) {
        self.food = food
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingLabel = State(initialValue: food?.servingLabel ?? "1 serving")
        _servingGrams = State(initialValue: (food?.servingGrams ?? 0) > 0 ? food?.servingGrams : nil)
        _values = State(initialValue: food?.nutrients ?? [:])
    }

    var body: some View {
        if food == nil {
            NavigationStack { form }
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section("Food") {
                TextField("Name (e.g. Egg, large)", text: $name)
                TextField("Brand (optional)", text: $brand)
            }
            Section {
                TextField("Serving (e.g. 1 egg, 1 cup)", text: $servingLabel)
                HStack {
                    Text("Serving weight")
                    Spacer()
                    TextField("optional", value: $servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("g").foregroundStyle(.secondary)
                }
            } header: {
                Text("Serving")
            } footer: {
                Text("Add the weight to be able to log this food in grams as well as by serving.")
            }
            Section("Nutrients per serving") {
                ForEach(Nutrient.allCases) { nutrient in
                    HStack {
                        Text(nutrient.name)
                        Spacer()
                        TextField("0", value: binding(for: nutrient), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(nutrient.unit)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle(food == nil ? "New Food" : "Edit Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if food == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func binding(for nutrient: Nutrient) -> Binding<Double?> {
        Binding(
            get: { values[nutrient.rawValue] },
            set: { values[nutrient.rawValue] = $0 }
        )
    }

    private func save() {
        let label = servingLabel.trimmingCharacters(in: .whitespaces)
        if let food {
            food.name = name
            food.brand = brand
            food.servingLabel = label.isEmpty ? "1 serving" : label
            food.servingGrams = servingGrams ?? 0
            food.nutrients = values
        } else {
            context.insert(Food(name: name, brand: brand,
                                servingLabel: label.isEmpty ? "1 serving" : label,
                                servingGrams: servingGrams ?? 0, nutrients: values))
        }
        dismiss()
    }
}
