import SwiftUI
import SwiftData
import PhotosUI

/// Log meals by describing them: dictate or type what you ate, optionally add photos, answer any questions
/// Claude has about amounts, then review the list before it goes into the day's log.
struct VoiceLogView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.createdAt, order: .reverse) private var foods: [Food]
    @AppStorage("usdaApiKey") private var usdaKey = ""

    @StateObject private var chat = MealChat()
    @StateObject private var recorder = SpeechRecorder()
    @State private var photos: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var editing: EditTarget?
    @State private var saveMatches = true
    @State private var isSending = false
    private let apiKey = KeychainStore.claudeAPIKey

    private struct EditTarget: Identifiable {
        let id: UUID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsInput {
                    inputBar
                }
            }
            .navigationTitle("Tell me what you ate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.clear()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isReviewing {
                        Button("Log all") { logAll() }
                            .disabled(chat.items.isEmpty)
                    }
                }
            }
            .sheet(item: $editing) { target in
                if let index = chat.items.firstIndex(where: { $0.id == target.id }) {
                    ProposedItemEditView(item: $chat.items[index])
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { photos.append($0) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, newItems in
                loadPickedPhotos(newItems)
            }
        }
    }

    private var isReviewing: Bool {
        if case .reviewing = chat.phase { return true }
        return false
    }

    private var showsInput: Bool {
        switch chat.phase {
        case .composing, .asking, .reviewing: return true
        case .working, .failed: return false
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch chat.phase {
        case .composing:
            composeIntro
        case .working(let status):
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        case .asking(let intro, let questions):
            questionsView(intro: intro, questions: questions)
        case .reviewing:
            reviewList
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                if chat.hasStarted {
                    Button("Try again") { chat.retry() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Start over") {
                    chat.phase = .composing
                }
            }
            .padding()
        }
    }

    private var composeIntro: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button {
                    recorder.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill((recorder.isRecording ? Color.red : Color.accentColor).opacity(0.12))
                            .frame(width: 150, height: 150)
                        Circle()
                            .fill((recorder.isRecording ? Color.red : Color.accentColor).opacity(0.18))
                            .frame(width: 110, height: 110)
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")

                Text(recorder.isRecording ? "Listening… tap to stop" : "Tap to talk, or type below")
                    .font(.headline)

                Text("For example: \"For breakfast I had 3 scrambled eggs and a cold brew with about a cup of Silk Original oat milk. For lunch…\" Rough amounts are fine; I'll ask if something matters. Add photos of a plate or a nutrition label too.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if apiKey.isEmpty {
                    Label("Add your Claude API key in Settings to use this.", systemImage: "key.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func questionsView(intro: String, questions: [ClarifyingQuestion]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !intro.isEmpty {
                    Text(intro)
                        .padding(12)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.text)
                            .font(.headline)
                        if !question.options.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(question.options, id: \.self) { option in
                                        Button(option) { addAnswer(option, to: question) }
                                            .buttonStyle(.bordered)
                                            .buttonBorderShape(.capsule)
                                    }
                                }
                            }
                        }
                    }
                }
                if !questions.isEmpty {
                    Text("Tap answers or say them, then send.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewList: some View {
        List {
            Section {
                if !chat.summary.isEmpty {
                    Text(chat.summary)
                }
                totalsRow
                Toggle("Save matched foods to My Foods", isOn: $saveMatches)
            } footer: {
                Text("Tap an item to adjust it, hold it to move it to another meal, swipe to remove it, or tell me what to change below.")
            }

            ForEach(Meal.allCases) { meal in
                let mealItems = chat.items.filter { $0.meal == meal }
                if !mealItems.isEmpty {
                    Section {
                        ForEach(mealItems) { item in
                            Button {
                                editing = EditTarget(id: item.id)
                            } label: {
                                ProposedItemRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                MoveToMealButtons(current: item.meal.rawValue) { newMeal in
                                    if let index = chat.items.firstIndex(where: { $0.id == item.id }) {
                                        chat.items[index].meal = newMeal
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    chat.items.removeAll { $0.id == item.id }
                                }
                            }
                        }
                    } header: {
                        MealHeader(meal: meal, calories: mealItems.reduce(0) { $0 + $1.eaten[.calories] })
                    }
                }
            }
        }
    }

    private var totalsRow: some View {
        let totals = chat.items.reduce(into: NutrientValues()) { $0 = $0.adding($1.eaten) }
        return HStack {
            Label("\(formatAmount(totals[.calories])) kcal", systemImage: "flame.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            Spacer()
            Text("P \(formatAmount(totals[.protein]))  C \(formatAmount(totals[.carbs]))  F \(formatAmount(totals[.fat])) g")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(photos.indices, id: \.self) { index in
                            Image(uiImage: photos[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.black.opacity(0.6))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            if let error = recorder.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    if CameraPicker.isAvailable {
                        Button { showingCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        Label("Choose photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }

                TextField(placeholder, text: $recorder.text, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(recorder.isRecording)

                Button {
                    recorder.toggle()
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
                }
                .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Dictate")

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var placeholder: String {
        switch chat.phase {
        case .asking: return "Your answer"
        case .reviewing: return "Something off? Tell me"
        default: return "What did you eat?"
        }
    }

    private var canSend: Bool {
        let hasText = !recorder.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !apiKey.isEmpty && !isSending && (hasText || !photos.isEmpty || recorder.isRecording)
    }

    // MARK: - Actions

    private func send() async {
        isSending = true
        defer { isSending = false }
        if recorder.isRecording {
            recorder.stop()
            // Give the recognizer a moment to deliver its final transcription.
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        let text = recorder.text
        let jpegs = photos.compactMap { $0.jpegForUpload() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !jpegs.isEmpty else { return }
        if case .composing = chat.phase {
            chat.start(text: text, photos: jpegs, savedFoods: foods, date: date, apiKey: apiKey, usdaKey: usdaKey)
        } else {
            chat.reply(text: text, photos: jpegs)
        }
        recorder.clear()
        photos = []
        pickerItems = []
    }

    private func addAnswer(_ option: String, to question: ClarifyingQuestion) {
        let line = "\(question.text) \(option)."
        let current = recorder.text.trimmingCharacters(in: .whitespacesAndNewlines)
        recorder.text = current.isEmpty ? line : "\(current)\n\(line)"
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photos.append(image)
                }
            }
            pickerItems = []
        }
    }

    private func logAll() {
        var savedKeys = Set(foods.map { "\($0.name)|\($0.brand)" })
        for (index, item) in chat.items.enumerated() {
            // A second apart keeps the entries in the order they were said.
            context.insert(LogEntry(date: date.addingTimeInterval(Double(index)), meal: item.meal,
                                    foodName: item.name, amountText: item.loggedAmountText,
                                    nutrients: item.eaten))
            if saveMatches, item.source == .usda, let match = item.match, !match.isSaved {
                let key = "\(match.name)|\(match.brand)"
                if !savedKeys.contains(key) {
                    savedKeys.insert(key)
                    context.insert(Food(name: match.name, brand: match.brand, servingLabel: match.servingLabel,
                                        servingGrams: match.servingGrams, nutrients: match.nutrients,
                                        portions: match.portions))
                }
            }
        }
        dismiss()
    }
}

/// One proposed food on the review screen.
struct ProposedItemRow: View {
    let item: ProposedItem

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                Text(item.loggedAmountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceText)
                    .font(.caption2)
                    .foregroundStyle(item.source == .estimate ? Color.orange : Color.secondary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(formatAmount(item.eaten[.calories])) kcal")
                Text("P \(formatAmount(item.eaten[.protein])) · C \(formatAmount(item.eaten[.carbs])) · F \(formatAmount(item.eaten[.fat]))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var sourceText: String {
        switch item.source {
        case .myFoods:
            return "My Foods · \(item.match?.name ?? "")"
        case .usda:
            let brand = item.match?.brand ?? ""
            return "USDA · \(item.match?.name ?? "")\(brand.isEmpty ? "" : " (\(brand))")"
        case .estimate:
            return "Claude's estimate"
        }
    }
}

/// Adjust one proposed food before logging it.
struct ProposedItemEditView: View {
    @Binding var item: ProposedItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                    TextField("Amount", text: $item.amountText)
                    Picker("Meal", selection: $item.meal) {
                        ForEach(Meal.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(value: $item.multiplier, in: 0.25...10, step: 0.25) {
                        HStack {
                            Text("Portion")
                            Spacer()
                            Text("× \(formatAmount(item.multiplier))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Portion scales the amount Claude proposed, e.g. × 1.5 for half as much again.")
                }

                Section("This amount contains") {
                    ForEach(Nutrient.allCases) { nutrient in
                        if item.nutrients[nutrient.rawValue] != nil {
                            HStack {
                                Text(nutrient.name)
                                Spacer()
                                Text("\(formatAmount(item.eaten[nutrient])) \(nutrient.unit)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
