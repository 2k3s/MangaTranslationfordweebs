import Foundation

protocol MangaTranslating {
    func fetchInstalledModels() async -> [String]
    func translateBubbles(
        _ japaneseBubbles: [String],
        model: String,
        glossary: [GlossaryEntry],
        recentContext: [(japanese: String, english: String)]
    ) async -> [String]
    func explainJapaneseBreakdown(_ japaneseText: String, model: String) async -> String
}

struct OllamaTranslationService: MangaTranslating {
    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
            let top_p: Double
            let repeat_penalty: Double
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let keep_alive: String
        let options: Options
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    private struct TagsResponse: Decodable {
        struct ModelEntry: Decodable {
            let name: String
        }
        let models: [ModelEntry]
    }

    func fetchInstalledModels() async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            return ["qwen2.5:7b"]
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ["qwen2.5:7b"]
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            let names = decoded.models.map(\.name).filter { !$0.isEmpty }
            return names.isEmpty ? ["qwen2.5:7b"] : names
        } catch {
            return ["qwen2.5:7b"]
        }
    }

    func translateBubbles(
        _ japaneseBubbles: [String],
        model: String = "qwen2.5:7b",
        glossary: [GlossaryEntry] = [],
        recentContext: [(japanese: String, english: String)] = []
    ) async -> [String] {
        guard !japaneseBubbles.isEmpty else { return [] }
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            return japaneseBubbles.map { _ in "Invalid Ollama URL" }
        }

        let numberedInput = japaneseBubbles.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        var glossaryInstruction = ""
        let activeGlossary = glossary.filter {
            !$0.japanese.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.english.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !activeGlossary.isEmpty {
            let terms = activeGlossary
                .map { "- \($0.japanese) = \($0.english)" }
                .joined(separator: "\n")
            glossaryInstruction = "\nMANDATORY GLOSSARY TERMS:\n\(terms)\n"
        }

        var contextInstruction = ""
        if !recentContext.isEmpty {
            let historyLines = recentContext
                .suffix(6)
                .map { "- \($0.japanese) -> \($0.english)" }
                .joined(separator: "\n")
            contextInstruction = """
            \nPREVIOUS SCENE DIALOGUE (for speaker/pronoun continuity ONLY — do NOT re-output these):
            \(historyLines)
            """
        }

        let systemPrompt = """
        You are an expert Japanese-to-English manga localizer (like Viz Media or Kodansha).
        The numbered lines below are consecutive speech bubbles from the same manga page in reading order.
        Read all lines together as a single conversation before translating each line.

        LOCALIZATION GUIDELINES:
        1. Write natural, idiomatic, spoken English that sounds like real people talking in a manga—never stiff, overly literal dictionary definitions.
           - Example: "言質も取ったし" -> "Nice, I got his promise too!" (NOT "I got the collateral").
           - Example: "ではまた明日" -> "Well then, see you tomorrow!" (NOT "Bright day").
           - Example: "フフフ…" / "ふふ" -> "Heheh..." (never transliterate laughter as "Fufufu" or "Faf").
           - Example: "なんでもなーい" -> "It's nothing at all~"
        2. Infer omitted Japanese pronouns (I, you, he, she, we) from the surrounding bubbles on the page.
        3. Keep each line concise enough to fit comfortably inside a speech bubble.
        4. Output strictly in English using the Latin alphabet ONLY. NEVER output any Chinese (Hanzi) or Japanese characters.
        5. Return ONLY the numbered lines [1], [2], ... on separate lines with zero extra commentary.\(glossaryInstruction)\(contextInstruction)
        """

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: numberedInput)
            ],
            stream: false,
            keep_alive: "30m",
            options: .init(temperature: 0.15, top_p: 0.85, repeat_penalty: 1.08)
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 35
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return japaneseBubbles.map { _ in "Ollama error (is 'ollama serve' running?)" }
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let rawReply = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.parseNumberedLines(rawReply, expectedCount: japaneseBubbles.count)
        } catch {
            return japaneseBubbles.map { _ in "Connection failed: run 'ollama pull \(model)'" }
        }
    }

    func explainJapaneseBreakdown(
        _ japaneseText: String,
        model: String = "qwen2.5:7b"
    ) async -> String {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            return "Invalid Ollama URL."
        }

        let systemPrompt = """
        You are a concise Japanese manga tutor.
        Break down the user's Japanese manga line word-by-word in 2 to 5 short bullet points.
        Format each bullet as:
        • Word (Hiragana / Romaji) — English meaning & nuance in context
        Keep it brief, accurate, and easy to scan.
        """

        let payload = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: japaneseText)
            ],
            stream: false,
            keep_alive: "30m",
            options: .init(temperature: 0.1, top_p: 0.85, repeat_penalty: 1.05)
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 25
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Could not reach Ollama."
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Breakdown failed: \(error.localizedDescription)"
        }
    }

    private static func parseNumberedLines(_ reply: String, expectedCount: Int) -> [String] {
        let lines = reply
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results = Array(repeating: "", count: expectedCount)

        for line in lines {
            if let closeBracket = line.firstIndex(of: "]"),
               line.hasPrefix("[") {
                let numStr = String(line[line.index(after: line.startIndex)..<closeBracket])
                if let index = Int(numStr), index >= 1, index <= expectedCount {
                    let textStart = line.index(after: closeBracket)
                    let cleaned = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                    results[index - 1] = stripCJKCharacters(from: cleaned)
                }
            }
        }

        for i in 0..<expectedCount where results[i].isEmpty {
            if i < lines.count {
                results[i] = stripCJKCharacters(from: lines[i])
            } else {
                results[i] = "..."
            }
        }

        return results
    }

    private static func stripCJKCharacters(from text: String) -> String {
        let filteredScalars = text.unicodeScalars.filter { scalar in
            let v = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x309F).contains(v)
                || (0x30A0...0x30FF).contains(v)
                || (0xFF66...0xFF9F).contains(v)
            return !isCJK
        }
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "..." : cleaned
    }
}
