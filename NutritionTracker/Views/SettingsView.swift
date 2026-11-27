import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var goals: GoalStore
    @AppStorage("usdaApiKey") private var apiKey = ""
    @State private var claudeKey = KeychainStore.claudeAPIKey

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
                    SecureField("sk-ant-…", text: $claudeKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: claudeKey) { _, newValue in
                            KeychainStore.claudeAPIKey = newValue
                        }
                    Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                } header: {
                    Text("Claude API key")
                } footer: {
                    Text("Used by \"Tell me what you ate\" to turn voice notes and photos into log entries. Kept in the iPhone Keychain. A logging session usually costs about 10 to 30 cents of API usage.")
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
