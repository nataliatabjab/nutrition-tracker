import SwiftUI
import SwiftData

/// Pick how much of a food was eaten, by serving, by household portion, or by weight.
struct LogFoodView: View {
    let draft: FoodDraft
    let date: Date
    let onLogged: () -> Void

    private enum UnitChoice: Hashable {
        case serving
        case portion(Int)
        case grams
    }

    @Environment(\.modelContext) private var context
    @State private var meal: Meal
    @State private var quantity: Double? = 1
    @State private var unit: UnitChoice
    @State private var saveToMyFoods = true

    init(draft: FoodDraft, meal: Meal, date: Date, onLogged: @escaping () -> Void) {
        self.draft = draft
        self.date = date
        self.onLogged = onLogged
        _meal = State(initialValue: meal)
        // USDA foods are per 100 g, so a household portion ("1 large") is a friendlier default.
        _unit = State(initialValue: draft.isSaved || draft.portions.isEmpty ? .serving : .portion(0))
    }

    /// How many base servings the chosen amount equals.
    private var factor: Double {
        let amount = quantity ?? 0
        switch unit {
        case .serving:
            return amount
        case .portion(let index):
            return amount * draft.portions[index].grams / draft.servingGrams
        case .grams:
            return amount / draft.servingGrams
        }
    }

    private var unitLabel: String {
        switch unit {
        case .serving: return draft.servingLabel
        case .portion(let index): return draft.portions[index].label
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
                    TextField("0", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Picker("Unit", selection: $unit) {
                    Text(draft.servingLabel).tag(UnitChoice.serving)
                    if draft.servingGrams > 0 {
                        ForEach(draft.portions.indices, id: \.self) { index in
                            Text("\(draft.portions[index].label) (\(formatAmount(draft.portions[index].grams)) g)")
                                .tag(UnitChoice.portion(index))
                        }
                        Text("grams").tag(UnitChoice.grams)
                    }
                }
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                if !draft.isSaved {
                    Toggle("Save to My Foods", isOn: $saveToMyFoods)
                }
            }

            Section("This amount contains") {
                ForEach(Nutrient.allCases) { nutrient in
                    if draft.nutrients[nutrient.rawValue] != nil {
                        HStack {
                            Text(nutrient.name)
                            Spacer()
                            Text("\(formatAmount(eaten[nutrient])) \(nutrient.unit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") { log() }
                    .disabled(factor <= 0)
            }
        }
    }

    private func log() {
        let amountText = unit == .grams
            ? "\(formatAmount(quantity ?? 0)) g"
            : "\(formatAmount(quantity ?? 0)) × \(unitLabel)"
        context.insert(LogEntry(date: date, meal: meal, foodName: draft.name,
                                amountText: amountText, nutrients: eaten))
        if !draft.isSaved && saveToMyFoods {
            context.insert(Food(name: draft.name, brand: draft.brand, servingLabel: draft.servingLabel,
                                servingGrams: draft.servingGrams, nutrients: draft.nutrients,
                                portions: draft.portions))
        }
        onLogged()
    }
}
