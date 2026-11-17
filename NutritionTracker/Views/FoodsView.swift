import SwiftUI
import SwiftData

/// The saved-foods library: browse, edit, delete and create foods.
struct FoodsView: View {
    @Query(sort: \Food.name) private var foods: [Food]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var filter = FoodFilter.all
    @State private var creatingFood = false
    @State private var creatingRecipe = false

    var body: some View {
        NavigationStack {
            List {
                if foods.isEmpty {
                    EmptyIllustration(symbol: "fork.knife", title: "No saved foods yet",
                                      message: "Foods you create or log from the USDA database are saved here.")
                } else {
                    CategoryFilterBar(selection: $filter, foods: foods)
                }
                ForEach(foods.filter { $0.matches(filter, query: query) }) { food in
                    NavigationLink {
                        if food.isRecipe {
                            RecipeEditView(recipe: food)
                        } else {
                            FoodEditView(food: food)
                        }
                    } label: {
                        FoodRow(food: food)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(food) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods and recipes")
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
    @State private var category: String
    @State private var portions: [Portion]
    @State private var newUnitName = ""
    @State private var newUnitGrams: Double?

    init(food: Food?) {
        self.food = food
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingLabel = State(initialValue: food?.servingLabel ?? "1 serving")
        _servingGrams = State(initialValue: (food?.servingGrams ?? 0) > 0 ? food?.servingGrams : nil)
        _values = State(initialValue: food?.nutrients ?? [:])
        _category = State(initialValue: food?.category ?? "")
        _portions = State(initialValue: food?.portions ?? [])
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
                CategoryPicker(category: $category)
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
                Text("Add the weight to be able to log this food in grams and other units as well as by serving.")
            }
            if (servingGrams ?? 0) > 0 {
                Section {
                    ForEach(portions, id: \.self) { portion in
                        HStack {
                            Text(portion.label)
                            Spacer()
                            Text("\(formatAmount(portion.grams)) g").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { portions.remove(atOffsets: $0) }
                    HStack {
                        TextField("e.g. 1 apple", text: $newUnitName)
                        TextField("g", value: $newUnitGrams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").foregroundStyle(.secondary)
                        Button {
                            addUnit()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newUnitName.trimmingCharacters(in: .whitespaces).isEmpty || (newUnitGrams ?? 0) <= 0)
                    }
                } header: {
                    Text("Other units")
                } footer: {
                    Text("Units let you log by count, like 2 eggs or 1 apple.")
                }
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

    private func addUnit() {
        guard let grams = newUnitGrams, grams > 0 else { return }
        portions.append(Portion(label: newUnitName.trimmingCharacters(in: .whitespaces), grams: grams))
        newUnitName = ""
        newUnitGrams = nil
    }

    private func save() {
        let label = servingLabel.trimmingCharacters(in: .whitespaces)
        let target = food ?? Food(name: name, servingLabel: "", servingGrams: 0, nutrients: [:])
        target.name = name
        target.brand = brand
        target.servingLabel = label.isEmpty ? "1 serving" : label
        target.servingGrams = servingGrams ?? 0
        target.nutrients = values
        target.category = category
        target.portions = portions
        if food == nil {
            context.insert(target)
        }
        dismiss()
    }
}
