import Foundation

/// Pure timeout deny payload for a queued decision entry.
public enum DecisionTimeout {
    public static func denyData(for entry: DecisionEntry, message: String = "Timed out") -> Data {
        let routeKind: RouteKind = entry.kind == .question ? .question : .permission
        return DecisionJSON.deny(
            for: routeKind,
            hookEventName: entry.hookEventName,
            message: message
        )
    }
}
