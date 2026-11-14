import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var goals: GoalStore
    @AppStorage("usdaApiKey") private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Nutrient.allCases) { nutrient in
                        HStack {
                            Text(nutrient.name)
                            Spacer()
                            TextField(formatAmount(nutrient.defaultTarget),
                                      value: binding(for: nutrient), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text(nutrient.unit)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                        }
                    }
                    Button("Reset to defaults", role: .destructive) { goals.reset() }
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Defaults are general reference values, not medical advice. Set these with your doctor.")
                }

                Section {
                    TextField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Get a free key", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                } header: {
                    Text("USDA food search")
                } footer: {
                    Text("Search works without a key but is limited to a few searches per hour.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func binding(for nutrient: Nutrient) -> Binding<Double?> {
        Binding(
            get: { goals.targets[nutrient.rawValue] },
            set: { goals.targets[nutrient.rawValue] = $0 }
        )
    }
}
