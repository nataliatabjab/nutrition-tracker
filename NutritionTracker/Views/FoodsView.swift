import SwiftUI
import SwiftData
import PhotosUI

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

/// Create a food by hand (pass nil), or edit a saved one. A photo of the nutrition label can fill in the
/// serving size and nutrients.
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

    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var scanMessage: String?
    @State private var scanFailed = false
    private let claudeKey = KeychainStore.claudeAPIKey

    init(food: Food?) {
        self.food = food
        _name = State(initialValue: food?.name ?? "")
        _brand = State(initialValue: food?.brand ?? "")
        _servingLabel = State(initialValue: food?.servingLabel ?? "")
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
                TextField("Name (e.g. Greek yogurt)", text: $name)
                TextField("Brand (optional)", text: $brand)
                CategoryPicker(category: $category)
            }

            labelSection

            Section {
                HStack {
                    Text("Serving size")
                    Spacer()
                    TextField("e.g. 2/3 cup", text: $servingLabel)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("optional", value: $servingGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("g").foregroundStyle(.secondary)
                }
            } header: {
                Text("One serving")
            } footer: {
                Text("Copy these from the top of the label. For \"Serving size 2/3 cup (55g)\", enter 2/3 cup and 55 g. With the weight, you can also log this food in grams.")
            }

            if (servingGrams ?? 0) > 0 {
                Section {
                    ForEach(portions, id: \.self) { portion in
                        HStack {
                            Text(portion.label)
                            Spacer()
                            Text("= \(formatAmount(portion.grams)) g").foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { portions.remove(atOffsets: $0) }
                    HStack {
                        TextField("e.g. 1 cookie", text: $newUnitName)
                        Text("=").foregroundStyle(.secondary)
                        TextField("0", value: $newUnitGrams, format: .number)
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
                    Text("Other amounts (optional)")
                } footer: {
                    Text("Only needed if you'd log it by something other than a serving or grams. For example, if a serving is 3 cookies, add 1 cookie so you can log a single cookie.")
                }
            }

            Section {
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
            } header: {
                Text(nutritionHeader)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isScanning)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in scan(image) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            loadPickedPhoto(item)
        }
    }

    private var nutritionHeader: String {
        let label = servingLabel.trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? "Nutrition facts per serving" : "Nutrition facts per serving (\(label))"
    }

    @ViewBuilder
    private var labelSection: some View {
        Section {
            if isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the label…").foregroundStyle(.secondary)
                }
            } else {
                if CameraPicker.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Snap the nutrition label", systemImage: "camera.viewfinder")
                    }
                    .disabled(claudeKey.isEmpty)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo or screenshot", systemImage: "photo.on.rectangle")
                }
                .disabled(claudeKey.isEmpty)
            }
            if let scanMessage {
                Text(scanMessage)
                    .font(.footnote)
                    .foregroundStyle(scanFailed ? Color.red : Color.secondary)
            }
        } header: {
            Text("Nutrition label")
        } footer: {
            if claudeKey.isEmpty {
                Text("Add your Claude API key in Settings to fill this form in from a photo of the label.")
            } else {
                Text("Fills in the serving size and nutrition facts below. Check them before you save. Each scan costs about a cent or two of API usage.")
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                scan(image)
            } else {
                scanFailed = true
                scanMessage = "Couldn't open that photo."
            }
            pickerItem = nil
        }
    }

    private func scan(_ image: UIImage) {
        guard let jpeg = image.jpegForUpload() else { return }
        isScanning = true
        scanMessage = nil
        scanFailed = false
        Task {
            do {
                let reading = try await NutritionLabelReader.read(photo: jpeg, name: name, brand: brand, apiKey: claudeKey)
                apply(reading)
            } catch {
                scanFailed = true
                scanMessage = error.localizedDescription
            }
            isScanning = false
        }
    }

    private func apply(_ reading: LabelReading) {
        if !reading.servingLabel.isEmpty {
            servingLabel = reading.servingLabel
        }
        if let grams = reading.servingGrams {
            servingGrams = grams
        }
        // Label values replace what's there; nutrients the label doesn't show are left as they were.
        values.merge(reading.nutrients) { _, label in label }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = reading.productName
        }
        if brand.trimmingCharacters(in: .whitespaces).isEmpty {
            brand = reading.brand
        }
        let count = reading.nutrients.count
        var message = "Filled in \(count) nutrient\(count == 1 ? "" : "s") from the label."
        if !reading.note.isEmpty {
            message += " \(reading.note)"
        }
        scanFailed = false
        scanMessage = message
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
