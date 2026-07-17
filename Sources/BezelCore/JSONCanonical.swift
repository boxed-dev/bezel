import Foundation

public enum JSONCanonical {
    /// Compare two JSON payloads for semantic equality (key order independent).
    public static func equal(_ a: Data, _ b: Data) -> Bool {
        guard
            let oa = try? JSONSerialization.jsonObject(with: a),
            let ob = try? JSONSerialization.jsonObject(with: b),
            let ca = try? JSONSerialization.data(withJSONObject: oa, options: [.sortedKeys]),
            let cb = try? JSONSerialization.data(withJSONObject: ob, options: [.sortedKeys])
        else {
            return a == b
        }
        return ca == cb
    }

    public static func canonicalString(_ data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data),
            let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
            let s = String(data: out, encoding: .utf8)
        else { return nil }
        return s
    }
}
