import Testing
import Foundation
import BezelCore

@Suite("PermissionSuggestions")
struct PermissionSuggestionsTests {
    @Test func parsesPermissionSuggestionsFromPayload() throws {
        let json = #"""
        {
          "hook_event_name":"PermissionRequest",
          "session_id":"s1",
          "tool_name":"Bash",
          "tool_input":{"command":"rtk ls supabase/migrations/ | tail -20"},
          "permission_suggestions":[
            {
              "type":"addRules",
              "rules":[{"toolName":"Bash","ruleContent":"rtk ls *"}],
              "behavior":"allow",
              "destination":"localSettings"
            }
          ]
        }
        """#
        let data = Data(json.utf8)
        let suggestions = try #require(PermissionSuggestions.json(from: data))
        let arr = PermissionSuggestions.array(from: suggestions)
        #expect(arr.count == 1)
        #expect(PermissionSuggestions.alwaysAllowDetail(from: suggestions) == "rtk ls *")
        #expect(PermissionSuggestions.alwaysAllowButtonTitle(from: suggestions).contains("rtk ls *"))
        #expect(PermissionSuggestions.alwaysAllowButtonTitle(from: suggestions).contains("ask again") || PermissionSuggestions.alwaysAllowButtonTitle(from: suggestions).hasPrefix("Don't"))
    }

    @Test func permissionAllowEchoesUpdatedPermissions() throws {
        let updates: [[String: Any]] = [[
            "type": "addRules",
            "rules": [["toolName": "Bash", "ruleContent": "rtk ls *"]],
            "behavior": "allow",
            "destination": "localSettings",
        ]]
        let data = DecisionJSON.permissionAllow(updatedPermissions: updates)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = obj?["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        let echoed = decision?["updatedPermissions"] as? [[String: Any]]
        #expect(echoed?.count == 1)
        #expect((echoed?.first?["type"] as? String) == "addRules")
    }

    @Test func ingressSurfacesSuggestionsAndCommandSummary() throws {
        let json = #"""
        {
          "hook_event_name":"PermissionRequest",
          "session_id":"s1",
          "tool_name":"Bash",
          "tool_input":{"command":"rtk ls supabase/migrations/ | tail -20"},
          "permission_suggestions":[
            {
              "type":"addRules",
              "rules":[{"toolName":"Bash","ruleContent":"rtk ls *"}],
              "behavior":"allow",
              "destination":"localSettings"
            }
          ]
        }
        """#
        let p = try HookPayload.parse(Data(json.utf8))
        let a = try #require(DecisionIngress.attention(for: p))
        #expect(a.kind == .permission)
        #expect(a.permissionSuggestionsJSON != nil)
        #expect(a.summary.contains("rtk ls"))
    }

    @Test func noSuggestionsWhenAbsent() throws {
        let p = try HookPayload.parse(Data(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash"}"#.utf8))
        let a = try #require(DecisionIngress.attention(for: p))
        #expect(a.permissionSuggestionsJSON == nil)
    }
}
