import Foundation

public struct QuestionOption: Codable, Sendable, Equatable, Hashable {
    public var label: String
    public var description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

public struct QuestionItem: Codable, Sendable, Equatable, Hashable {
    public var question: String
    public var header: String?
    public var options: [QuestionOption]
    public var multiSelect: Bool

    public init(question: String, header: String? = nil, options: [QuestionOption], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }

    public func asDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "question": question,
            "options": options.map { opt -> [String: Any] in
                var o: [String: Any] = ["label": opt.label]
                if let description = opt.description { o["description"] = description }
                return o
            },
            "multiSelect": multiSelect,
        ]
        if let header { d["header"] = header }
        return d
    }
}

public enum QuestionParser {
    public static func parse(fromToolInput toolInput: [String: Any]?) -> [QuestionItem] {
        guard let raw = toolInput?["questions"] as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            guard let question = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { opt -> QuestionOption? in
                guard let label = opt["label"] as? String else { return nil }
                return QuestionOption(label: label, description: opt["description"] as? String)
            }
            return QuestionItem(
                question: question,
                header: item["header"] as? String,
                options: options,
                multiSelect: item["multiSelect"] as? Bool ?? false
            )
        }
    }

    public static func toolInput(from rawJSON: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any] else { return nil }
        if let ti = obj["tool_input"] as? [String: Any] { return ti }
        if let ti = obj["toolInput"] as? [String: Any] { return ti }
        return nil
    }
}
