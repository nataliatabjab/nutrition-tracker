import SwiftUI
import SwiftData

/// Pick how much of a food was eaten, by serving, by household unit ("1 large", "1 apple"), or by weight.
/// With `onIngredient` set, the amount goes to a recipe instead of the day's log.
struct LogFoodView: View {
    let draft: FoodDraft
    let date: Date
    var onIngredient: ((Ingredient) -> Void)?
    let onLogged: () -> Void

    private enum UnitChoice: Hashable {
        case serving
        case portion(Int)
        case grams
    }

    @Environment(\.modelContext) private var context
    @AppStorage("usdaApiKey") private var apiKey = ""
    @State private var meal: Meal
    @State private var quantity: Double? = 1
    @State private var unit: UnitChoice
    @State private var portions: [Portion]
    @State private var saveToMyFoods = true
    @State private var loadingPortions = false
    @State private var addingUnit = false
    @State private var newUnitName = ""
    @State private var newUnitGrams = ""

    init(draft: FoodDraft, meal: Meal, date: Date, onIngredient: ((Ingredient) -> Void)? = nil,
         onLogged: @escaping () -> Void) {
        self.draft = draft
        self.date = date
        self.onIngredient = onIngredient
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
        _portions = State(initialValue: draft.portions)
        // A household unit ("1 large") is friendlier than "100 g", so prefer one when there is one.
        _unit = State(initialValue: draft.portions.isEmpty || draft.servingGrams <= 0 ? .serving : .portion(0))
    }

    private var canUseWeight: Bool { draft.servingGrams > 0 }

    /// How many base servings the chosen amount equals.
    private var factor: Double {
        let amount = quantity ?? 0
        switch unit {
        case .serving:
            return amount
        case .portion(let index):
            guard portions.indices.contains(index), canUseWeight else { return 0 }
            return amount * portions[index].grams / draft.servingGrams
        case .grams:
            return canUseWeight ? amount / draft.servingGrams : 0
        }
    }

    private var unitLabel: String {
        switch unit {
        case .serving: return draft.servingLabel
        case .portion(let index): return portions.indices.contains(index) ? portions[index].label : ""
        case .grams: return "g"
        }
    }

    private var eaten: NutrientValues {
        draft.nutrients.scaled(by: factor)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Amount")
                    Spacer()
                    Button { step(-1) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled((quantity ?? 0) <= 0)
                    TextField("0", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                    Button { step(1) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.borderless)
                }
                .font(.title3)

                Picker("Unit", selection: $unit) {
                    if canUseWeight {
                        ForEach(portions.indices, id: \.self) { index in
                            Text("\(portions[index].label) (\(formatAmount(portions[index].grams)) g)")
                                .tag(UnitChoice.portion(index))
                        }
                    }
                    Text(draft.servingLabel).tag(UnitChoice.serving)
                    if canUseWeight {
                        Text("grams").tag(UnitChoice.grams)
                    }
                }
                if loadingPortions {
                    HStack {
                        ProgressView()
                        Text("Looking up units…").foregroundStyle(.secondary)
                    }
                }
                if canUseWeight {
                    Button {
                        addingUnit = true
                    } label: {
                        Label("Add a unit (e.g. 1 apple)", systemImage: "plus")
                    }
                }

                if onIngredient == nil {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.title).tag($0) }
                    }
                }
                if !draft.isSaved {
                    Toggle("Save to My Foods", isOn: $saveToMyFoods)
                }
            }

            Section("This amount contains") {
                ForEach(Nutrient.allCases) { nutrient in
                    if draft.nutrients[nutrient.rawValue] != nil {
                        HStack(spacing: 12) {
                            IconBadge(symbol: nutrient.symbol, color: nutrient.color, size: 26)
                            Text(nutrient.name)
                            Spacer()
                            Text("\(formatAmount(eaten[nutrient])) \(nutrient.unit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(onIngredient == nil ? "Log" : "Add") { log() }
                    .disabled(factor <= 0)
            }
        }
        .alert("Add a unit", isPresented: $addingUnit) {
            TextField("Name, e.g. 1 apple", text: $newUnitName)
            TextField("Weight in grams", text: $newUnitGrams)
                .keyboardType(.decimalPad)
            Button("Add") { addUnit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How much does one of these weigh? A kitchen scale or the package label helps.")
        }
        .task { await loadPortionsIfNeeded() }
    }

    private func step(_ delta: Double) {
        let current = quantity ?? 0
        // Whole units step by 1; grams step by 10.
        let size = unit == .grams ? 10 * delta : delta
        quantity = max(0, (current + size).rounded())
    }

    private func addUnit() {
        let name = newUnitName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let grams = Double(newUnitGrams.replacingOccurrences(of: ",", with: ".")), grams > 0 else { return }
        portions.insert(Portion(label: name, grams: grams), at: 0)
        if let food = draft.food { food.portions = portions }
        unit = .portion(0)
        quantity = 1
        newUnitName = ""
        newUnitGrams = ""
    }

    /// USDA search results often lack household units, so fetch them for the food on demand.
    private func loadPortionsIfNeeded() async {
        guard portions.isEmpty, draft.fdcId > 0, canUseWeight else { return }
        loadingPortions = true
        defer { loadingPortions = false }
        guard let found = try? await USDAService.portions(fdcId: draft.fdcId, apiKey: apiKey),
              !found.isEmpty, portions.isEmpty else { return }
        portions = found
        if let food = draft.food { food.portions = found }
        if unit == .serving {
            unit = .portion(0)
            quantity = 1
        }
    }

    private func log() {
        let amountText = unit == .grams
            ? "\(formatAmount(quantity ?? 0)) g"
            : "\(formatAmount(quantity ?? 0)) × \(unitLabel)"
        if let onIngredient {
            onIngredient(Ingredient(name: draft.name, amountText: amountText,
                                    grams: factor * draft.servingGrams, nutrients: eaten))
        } else {
            context.insert(LogEntry(date: date, meal: meal, foodName: draft.name,
                                    amountText: amountText, nutrients: eaten))
        }
        if !draft.isSaved && saveToMyFoods {
            let food = Food(name: draft.name, brand: draft.brand, servingLabel: draft.servingLabel,
                            servingGrams: draft.servingGrams, nutrients: draft.nutrients,
                            portions: portions)
            food.category = draft.category
            food.fdcId = draft.fdcId
            context.insert(food)
        }
        onLogged()
    }
}
