import Foundation
import SwiftUI

/// One food Claude proposes to log, ready for review.
struct ProposedItem: Identifiable {
    enum Source {
        case myFoods
        case usda
        case estimate
    }

    let id = UUID()
    var meal: Meal
    var name: String
    var amountText: String
    /// Nutrients for the proposed amount.
    var nutrients: NutrientValues
    /// Lets the amount be scaled on the review screen without asking Claude again.
    var multiplier: Double = 1
    var source: Source
    /// The database food it was matched to, if any.
    var match: FoodDraft?
    var note: String

    var eaten: NutrientValues { nutrients.scaled(by: multiplier) }

    var loggedAmountText: String {
        multiplier == 1 ? amountText : "\(amountText) × \(formatAmount(multiplier))"
    }
}

/// A clarifying question from Claude, with suggested answers.
struct ClarifyingQuestion: Identifiable {
    let id = UUID()
    var text: String
    var options: [String]
}

/// Runs the conversation with Claude that turns a voice note (and photos) into log entries.
///
/// Claude has three tools: `search_foods` (answered by the app from My Foods and USDA, then the loop continues),
/// `ask_questions` and `propose_log` (both shown to the user; their answer becomes the tool result).
@MainActor
final class MealChat: ObservableObject {
    enum Phase {
        case composing
        case working(String)
        case asking(intro: String, questions: [ClarifyingQuestion])
        case reviewing
        case failed(String)
    }

    @Published var phase: Phase = .composing
    @Published var items: [ProposedItem] = []
    @Published var summary = ""

    private var messages: [[String: Any]] = []
    /// Foods Claude can refer to by id: saved foods ("mine-3") and search results ("usda-12").
    private var candidates: [String: FoodDraft] = [:]
    private var usdaCount = 0
    /// Tool results that wait for the user's reply before they go back to Claude.
    private var heldResults: [[String: Any]] = []
    /// The tool call the user's next message answers; nil when Claude asked in plain text.
    private var pendingToolID: String?
    private var pendingKind = ""
    private var system = ""
    private var apiKey = ""
    private var usdaKey = ""
    private var savedFoods: [FoodDraft] = []

    var hasStarted: Bool { !messages.isEmpty }

    func start(text: String, photos: [Data], savedFoods foods: [Food], date: Date, apiKey: String, usdaKey: String) {
        self.apiKey = apiKey
        self.usdaKey = usdaKey
        savedFoods = foods.prefix(200).map { FoodDraft(food: $0) }
        candidates = [:]
        for (index, draft) in savedFoods.enumerated() {
            candidates["mine-\(index)"] = draft
        }
        system = Self.systemPrompt(savedFoods: savedFoods)
        messages = []
        heldResults = []
        pendingToolID = nil
        items = []

        let dayText = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let timeText = Date().formatted(date: .omitted, time: .shortened)
        var intro = "I'm logging food for \(dayText). It's \(timeText) now (only use the time if I don't say which meal)."
        if !photos.isEmpty {
            intro += " I attached \(photos.count) photo\(photos.count == 1 ? "" : "s")."
        }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var content: [[String: Any]] = photos.map { ClaudeClient.imageBlock(jpeg: $0) }
        content.append(ClaudeClient.textBlock(note.isEmpty ? intro : "\(intro)\n\nVoice note:\n\(note)"))
        messages.append(["role": "user", "content": content])
        Task { await run() }
    }

    /// The user's answer to questions, or a correction to the proposed list.
    func reply(text: String, photos: [Data]) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = heldResults
        heldResults = []
        if let pendingToolID {
            let prefix = pendingKind == "propose_log" ? "Natalia wants changes to the list" : "Natalia's answers"
            content.append(ClaudeClient.toolResult(id: pendingToolID, content: "\(prefix): \(answer)"))
        }
        content += photos.map { ClaudeClient.imageBlock(jpeg: $0) }
        if pendingToolID == nil || !photos.isEmpty {
            content.append(ClaudeClient.textBlock(pendingToolID == nil ? answer : "Photo attached with my reply."))
        }
        pendingToolID = nil
        messages.append(["role": "user", "content": content])
        Task { await run() }
    }

    func retry() {
        Task { await run() }
    }

    private func run() async {
        phase = .working("Reading what you ate…")
        do {
            for _ in 0..<12 {
                let response = try await ClaudeClient.send(apiKey: apiKey, system: system,
                                                           tools: Self.tools, messages: messages)
                let stopReason = response["stop_reason"] as? String ?? ""
                if stopReason == "refusal" { throw ClaudeClient.ClaudeError.refused }
                if stopReason == "max_tokens" { throw ClaudeClient.ClaudeError.cutOff }
                guard let content = response["content"] as? [[String: Any]] else {
                    throw ClaudeClient.ClaudeError.badResponse
                }
                messages.append(["role": "assistant", "content": content])

                let toolUses = content.filter { $0["type"] as? String == "tool_use" }
                if toolUses.isEmpty {
                    // Claude answered in plain text; treat it as a question.
                    let texts: [String] = content.compactMap { block in
                        guard block["type"] as? String == "text" else { return nil }
                        return block["text"] as? String
                    }
                    let text = texts.joined(separator: "\n")
                    pendingToolID = nil
                    phase = .asking(intro: text.isEmpty ? "Anything else to add?" : text, questions: [])
                    return
                }

                var results: [[String: Any]] = []
                var question: (id: String, input: [String: Any])?
                var proposal: (id: String, input: [String: Any])?
                for use in toolUses {
                    let id = use["id"] as? String ?? ""
                    let input = use["input"] as? [String: Any] ?? [:]
                    switch use["name"] as? String ?? "" {
                    case "search_foods":
                        let queries = (input["queries"] as? [String]) ?? []
                        phase = .working("Looking up \(queries.prefix(3).joined(separator: ", "))…")
                        results.append(ClaudeClient.toolResult(id: id, content: await search(queries)))
                    case "ask_questions":
                        if question == nil { question = (id, input) } else {
                            results.append(ClaudeClient.toolResult(id: id, content: "Ask all questions in one call.", isError: true))
                        }
                    case "propose_log":
                        if proposal == nil { proposal = (id, input) } else {
                            results.append(ClaudeClient.toolResult(id: id, content: "Propose the full list in one call.", isError: true))
                        }
                    default:
                        results.append(ClaudeClient.toolResult(id: id, content: "Unknown tool.", isError: true))
                    }
                }

                if let question {
                    if let proposal {
                        results.append(ClaudeClient.toolResult(id: proposal.id, content: "Not shown: answer questions first, then propose again."))
                    }
                    heldResults = results
                    pendingToolID = question.id
                    pendingKind = "ask_questions"
                    phase = .asking(intro: question.input["intro"] as? String ?? "",
                                    questions: Self.parseQuestions(question.input))
                    return
                }
                if let proposal {
                    heldResults = results
                    pendingToolID = proposal.id
                    pendingKind = "propose_log"
                    items = parseItems(proposal.input)
                    summary = proposal.input["summary"] as? String ?? ""
                    phase = .reviewing
                    return
                }
                messages.append(["role": "user", "content": results])
            }
            phase = .failed("Claude took too many steps. Try describing fewer meals at once.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Food search

    private func search(_ queries: [String]) async -> String {
        let key = usdaKey
        let usdaResults: [(Int, Result<[FoodDraft], Error>)] = await withTaskGroup(of: (Int, Result<[FoodDraft], Error>).self) { group in
            for (index, query) in queries.prefix(12).enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await USDAService.search(query, apiKey: key)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[FoodDraft], Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var output: [[String: Any]] = []
        for (index, query) in queries.prefix(12).enumerated() {
            var entry: [String: Any] = ["query": query]
            let words = query.lowercased().split(separator: " ").map(String.init)
            let mine = savedFoods.enumerated().filter { _, draft in
                let haystack = "\(draft.name) \(draft.brand)".lowercased()
                return words.contains { $0.count > 2 && haystack.contains($0) }
            }
            entry["my_foods"] = mine.prefix(5).map { Self.describe($0.element, id: "mine-\($0.offset)") }

            switch usdaResults.first(where: { $0.0 == index })?.1 {
            case .success(let drafts):
                entry["usda"] = drafts.prefix(8).map { draft -> [String: Any] in
                    usdaCount += 1
                    let id = "usda-\(usdaCount)"
                    candidates[id] = draft
                    return Self.describe(draft, id: id)
                }
            case .failure(let error):
                entry["usda_error"] = "\(error.localizedDescription) Use My Foods or your own estimate."
            case nil:
                entry["usda"] = []
            }
            output.append(entry)
        }
        if queries.count > 12 {
            output.append(["note": "Only the first 12 queries were searched."])
        }
        let data = (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func describe(_ draft: FoodDraft, id: String) -> [String: Any] {
        var item: [String: Any] = [
            "id": id,
            "name": draft.name,
            "per": draft.servingGrams > 0 ? "\(draft.servingLabel) (\(formatAmount(draft.servingGrams)) g)" : draft.servingLabel,
            "kcal": round1(draft.nutrients[.calories]),
            "protein_g": round1(draft.nutrients[.protein]),
            "carbs_g": round1(draft.nutrients[.carbs]),
            "fat_g": round1(draft.nutrients[.fat]),
        ]
        if !draft.brand.isEmpty { item["brand"] = draft.brand }
        if !draft.portions.isEmpty {
            item["portions"] = draft.portions.prefix(6).map { "\($0.label) = \(formatAmount($0.grams)) g" }
        }
        return item
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    // MARK: - Parsing tool input

    private static func parseQuestions(_ input: [String: Any]) -> [ClarifyingQuestion] {
        let raw = input["questions"] as? [[String: Any]] ?? []
        return raw.compactMap { question in
            guard let text = question["question"] as? String, !text.isEmpty else { return nil }
            return ClarifyingQuestion(text: text, options: question["options"] as? [String] ?? [])
        }
    }

    private func parseItems(_ input: [String: Any]) -> [ProposedItem] {
        let raw = input["items"] as? [[String: Any]] ?? []
        return raw.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let meal = Meal(rawValue: (item["meal"] as? String ?? "").lowercased()) ?? .snack
            let amount = item["amount"] as? String ?? ""
            let grams = jsonNumber(item["grams"]) ?? 0
            let servings = jsonNumber(item["servings"]) ?? 0
            var estimate: NutrientValues = [:]
            let estimateInput = item["estimate"] as? [String: Any] ?? [:]
            for nutrient in Nutrient.allCases {
                if let value = jsonNumber(estimateInput[nutrient.rawValue]) {
                    estimate[nutrient] = max(value, 0)
                }
            }

            var nutrients = estimate
            var source = ProposedItem.Source.estimate
            var match: FoodDraft?
            if let id = item["food_id"] as? String, let draft = candidates[id] {
                var factor = 0.0
                if grams > 0, draft.servingGrams > 0 {
                    factor = grams / draft.servingGrams
                } else if servings > 0 {
                    factor = servings
                }
                if factor > 0 {
                    // Database values first; Claude's estimate fills nutrients the database lacks (often iodine).
                    nutrients = estimate.merging(draft.nutrients.scaled(by: factor)) { _, database in database }
                    source = id.hasPrefix("mine-") ? .myFoods : .usda
                    match = draft
                }
            }
            return ProposedItem(meal: meal, name: name, amountText: amount, nutrients: nutrients,
                                source: source, match: match, note: item["note"] as? String ?? "")
        }
    }

    // MARK: - Prompt and tools

    private static func systemPrompt(savedFoods: [FoodDraft]) -> String {
        var prompt = """
        You help Natalia log what she ate in her personal nutrition tracking app. She describes her meals in a \
        voice note that was transcribed on her phone, so expect speech recognition mistakes (homophones, brand \
        names spelled oddly, missing punctuation). She may attach photos of a plate, packaging or a nutrition label.

        Turn what she says into food log entries:
        1. Split it into individual foods and put each under breakfast, lunch, dinner or snack. When she names \
        a meal ("for breakfast I had…", "this morning", "at dinner"), every food she lists for it goes under that \
        meal, even if it's now later in the day. She often logs meals hours after eating them. \
        Brunch counts as breakfast. Use the current time of day only for foods where she gives no hint at all.
        2. Call search_foods once with a query for every food to get nutrition data. Prefer her saved foods \
        (listed below) when they match what she ate. For branded products (for example "Silk Original oat \
        milk"), include the brand in the query. For cooked foods, prefer an entry that matches how it was \
        prepared (scrambled eggs rather than raw eggs). Search again with different wording only if nothing fits.
        3. If an amount is unclear in a way that changes calories meaningfully ("some pasta", "a bowl of rice", \
        "a handful of almonds", oil or butter used for cooking, the size of a coffee drink), call ask_questions. \
        Ask only what matters, at most four short questions at a time, each with two to four likely answers. \
        Assume the obvious instead of asking (eggs are large, a cup is 240 ml, a coffee with no size is 12 fl \
        oz). Ask at most twice in a session; after that, make your best estimate and say so in the note.
        4. Call propose_log with the full list. For each item give the best matching food_id (or null), the \
        weight in grams of the amount she ate (convert household measures with the portion sizes from the \
        search results; for drinks 1 ml is about 1 g), and your own estimate of every nutrient for that \
        amount. The estimate is used when no database food fits and to fill nutrients the database lacks. \
        Note any assumption briefly.

        Include drinks, milk in coffee, sauces, dressings and cooking fat when she mentions them, but don't add \
        foods she didn't mention. Photos of nutrition labels override database values. If she replies to a \
        proposal with corrections, apply them and call propose_log again with the complete updated list.

        Always respond by calling one of your tools.
        """
        if savedFoods.isEmpty {
            prompt += "\n\nShe has no saved foods yet."
        } else {
            prompt += "\n\nHer saved foods (id: name, brand, nutrients per serving):"
            for (index, draft) in savedFoods.enumerated() {
                let brand = draft.brand.isEmpty ? "" : " (\(draft.brand))"
                let per = draft.servingGrams > 0 ? "\(draft.servingLabel), \(formatAmount(draft.servingGrams)) g" : draft.servingLabel
                prompt += "\n- mine-\(index): \(draft.name)\(brand), per \(per): \(formatAmount(draft.nutrients[.calories])) kcal"
            }
        }
        return prompt
    }

    private static let nutrientProperties: [String: Any] = {
        var properties: [String: Any] = [:]
        for nutrient in Nutrient.allCases {
            properties[nutrient.rawValue] = ["type": "number", "description": "\(nutrient.name) in \(nutrient.unit)"]
        }
        return properties
    }()

    private typealias JSON = [String: Any]

    static let tools: [[String: Any]] = {
        let searchFoods: JSON = [
            "name": "search_foods",
            "description": "Search Natalia's saved foods and the USDA FoodData Central database. Pass every food you need in one call. Returns candidates with ids, nutrients per serving and household portion sizes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "queries": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "One short search query per food, e.g. \"egg scrambled\", \"silk original oat milk\", \"cold brew coffee\".",
                    ] as JSON,
                ] as JSON,
                "required": ["queries"],
            ] as JSON,
        ]

        let question: JSON = [
            "type": "object",
            "properties": [
                "question": ["type": "string"],
                "options": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Two to four likely short answers.",
                ] as JSON,
            ] as JSON,
            "required": ["question", "options"],
        ]
        let askQuestions: JSON = [
            "name": "ask_questions",
            "description": "Ask Natalia clarifying questions about amounts or details that change the nutrients meaningfully. Her answer comes back as the result.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "intro": ["type": "string", "description": "One short friendly sentence before the questions."],
                    "questions": ["type": "array", "items": question] as JSON,
                ] as JSON,
                "required": ["intro", "questions"],
            ] as JSON,
        ]

        let estimate: JSON = [
            "type": "object",
            "description": "Your estimate of every nutrient for the amount eaten.",
            "properties": nutrientProperties,
            "required": Nutrient.allCases.map(\.rawValue),
        ]
        let item: JSON = [
            "type": "object",
            "properties": [
                "meal": [
                    "type": "string",
                    "enum": ["breakfast", "lunch", "dinner", "snack"],
                    "description": "The meal she named for this food. Guess from the time only if she named none.",
                ] as JSON,
                "name": ["type": "string", "description": "Short friendly name, e.g. \"Scrambled eggs\"."],
                "amount": ["type": "string", "description": "The amount in her words, e.g. \"3 large eggs\" or \"1 cup\"."],
                "food_id": [
                    "type": ["string", "null"],
                    "description": "Id from the search results or her saved foods, or null to use the estimate.",
                ] as JSON,
                "grams": ["type": ["number", "null"], "description": "Weight of the amount eaten in grams."] as JSON,
                "servings": [
                    "type": ["number", "null"],
                    "description": "Number of servings of the matched food, when its serving has no gram weight.",
                ] as JSON,
                "estimate": estimate,
                "note": ["type": "string", "description": "Brief assumption or caveat, or an empty string."],
            ] as JSON,
            "required": ["meal", "name", "amount", "food_id", "grams", "servings", "estimate", "note"],
        ]
        let proposeLog: JSON = [
            "name": "propose_log",
            "description": "Show Natalia the complete list of foods to log for her review. She either confirms it or replies with corrections.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "summary": ["type": "string", "description": "One short sentence summarizing what's being logged."],
                    "items": ["type": "array", "items": item] as JSON,
                ] as JSON,
                "required": ["summary", "items"],
            ] as JSON,
        ]
        return [searchFoods, askQuestions, proposeLog]
    }()
}
