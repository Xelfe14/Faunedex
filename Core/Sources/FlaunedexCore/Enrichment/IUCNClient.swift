import Foundation

/// IUCN Red List API v4 (Bearer token, non-commercial). The v4 payload shapes
/// have shifted over time, so parsing walks the JSON for the relevant keys
/// rather than binding to a brittle fixed schema. Wikidata P141 remains the
/// keyless fallback if the token is missing or a response shape is unexpected.
public enum IUCNClient {

    public static func taxaURL(genus: String, species: String) -> URL {
        var c = URLComponents(url: FlaunedexConfig.iucnBaseURL.appendingPathComponent("taxa/scientific_name"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "genus_name", value: genus),
            URLQueryItem(name: "species_name", value: species),
        ]
        return c.url!
    }

    public static func assessmentURL(id: Int) -> URL {
        FlaunedexConfig.iucnBaseURL.appendingPathComponent("assessment/\(id)")
    }

    public static func authHeaders(token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "Accept": "application/json"]
    }

    /// Assessment ids found in a taxa response, newest-scoped first is not
    /// guaranteed — callers pick the Europe-scoped assessment downstream.
    public static func parseAssessmentIDs(_ data: Data) -> [Int] {
        let obj = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        var ids: [Int] = []
        JSONWalk.collectInts(obj, keys: ["assessment_id", "id"], into: &ids)
        return ids
    }

    /// Extract a Red List category code (e.g. "LC") from an assessment payload.
    public static func parseCategory(_ data: Data) -> String? {
        let obj = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        return JSONWalk.firstString(obj, keys: [
            "red_list_category_code", "category_code", "code", "red_list_category",
        ])
    }
}

/// Small helpers to pull values out of an untyped JSON object graph.
enum JSONWalk {
    static func firstString(_ node: Any, keys: Set<String>) -> String? {
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                if keys.contains(k), let s = v as? String, !s.isEmpty { return s }
            }
            for (_, v) in dict {
                if let found = firstString(v, keys: keys) { return found }
            }
        } else if let arr = node as? [Any] {
            for v in arr {
                if let found = firstString(v, keys: keys) { return found }
            }
        }
        return nil
    }

    static func collectInts(_ node: Any, keys: Set<String>, into out: inout [Int]) {
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                if keys.contains(k) {
                    if let i = v as? Int { out.append(i) }
                    else if let s = v as? String, let i = Int(s) { out.append(i) }
                }
            }
            for (_, v) in dict { collectInts(v, keys: keys, into: &out) }
        } else if let arr = node as? [Any] {
            for v in arr { collectInts(v, keys: keys, into: &out) }
        }
    }
}
