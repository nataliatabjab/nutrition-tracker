import SwiftUI
import SwiftData

/// Choose a food to log to a meal, or (with `onIngredient` set) to add to a recipe.
struct AddFoodView: View {
    var meal: Meal = .snack
    var date: Date = Date()
    var onIngredient: ((Ingredient) -> Void)?

    private enum Source: String, CaseIterable {
        case myFoods = "My Foods"
        case usda = "USDA Search"
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]
    @AppStorage("usdaApiKey") private var apiKey = ""

    @State private var source = Source.myFoods
    @State private var query = ""
    @State private var results: [FoodDraft] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var creatingFood = false
    @State private var creatingRecipe = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch source {
                case .myFoods: myFoodsRows
                case .usda: usdaRows
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: source == .myFoods ? "Filter my foods" : "Search, then press return")
            .onSubmit(of: .search) {
                if source == .usda { runSearch() }
            }
            .navigationTitle(onIngredient == nil ? "Add to \(meal.title)" : "Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { creatingFood = true } label: { Label("New food", systemImage: "fork.knife") }
                        if onIngredient == nil {
                            Button { creatingRecipe = true } label: { Label("New recipe", systemImage: "book.fill") }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
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

    @ViewBuilder
    private var myFoodsRows: some View {
        let shown = foods.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        if foods.isEmpty {
            EmptyIllustration(symbol: "fork.knife", title: "No saved foods yet",
                              message: "Tap + to create one, or search the USDA database.")
        } else if shown.isEmpty {
            Text("No saved foods match.")
                .foregroundStyle(.secondary)
        }
        ForEach(shown) { food in
            row(for: FoodDraft(food: food))
        }
    }

    @ViewBuilder
    private var usdaRows: some View {
        if isSearching {
            ProgressView()
        } else if let errorMessage {
            Text(errorMessage).foregroundStyle(.red)
        } else if results.isEmpty {
            EmptyIllustration(symbol: "magnifyingglass", title: "Search the USDA database",
                              message: "Try foods like \"egg\", \"apple\" or \"oatmeal\", then press return.")
        }
        ForEach(results.indices, id: \.self) { index in
            row(for: results[index])
        }
    }

    private func row(for draft: FoodDraft) -> some View {
        NavigationLink {
            LogFoodView(draft: draft, meal: meal, date: date, onIngredient: onIngredient) { dismiss() }
        } label: {
            VStack(alignment: .leading) {
                Text(draft.name)
                Text(subtitle(for: draft))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for draft: FoodDraft) -> String {
        let calories = "\(formatAmount(draft.nutrients[.calories])) kcal per \(draft.servingLabel)"
        return draft.brand.isEmpty ? calories : "\(draft.brand) · \(calories)"
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await USDAService.search(text, apiKey: apiKey)
                if results.isEmpty { errorMessage = "No foods found." }
            } catch {
                results = []
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }
}
