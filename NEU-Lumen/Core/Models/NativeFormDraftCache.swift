import Foundation

/// Short-lived native edits stay with their WebKit document, never on disk.
/// A changed order, field definition, page or identity invalidates the draft.
struct NativeFormDraftCache {
    private struct Draft {
        let url: URL
        let epoch: UUID
        let signature: Data
        let values: [String: String]
    }
    private var draft: Draft?

    mutating func clear() { draft = nil }

    func matchesContext(_ previous: NativeServiceDocument, _ next: NativeServiceDocument) -> Bool {
        guard let before = signature(previous), let after = signature(next) else { return false }
        return before == after
    }

    mutating func save(document: NativeServiceDocument, values: [String: String], url: URL, epoch: UUID) {
        draft = nil
        guard let signature = signature(document) else { return }
        var edits: [String: String] = [:]
        var keys: Set<String> = []
        for field in document.fields {
            guard let key = field.key, !key.isEmpty else { continue }
            guard keys.insert(key).inserted else { return }
            guard !field.readOnly, let value = values[field.id], value != field.value,
                  accepts(value, for: field) else { continue }
            edits[key] = value
        }
        if !edits.isEmpty { draft = Draft(url: url, epoch: epoch, signature: signature, values: edits) }
    }

    mutating func take(for document: NativeServiceDocument, url: URL, epoch: UUID) -> [String: String] {
        let previous = draft
        draft = nil
        guard let previous, previous.url == url, previous.epoch == epoch,
              signature(document) == previous.signature else { return [:] }
        let keyed = document.fields.compactMap(\.key)
        guard Set(keyed).count == keyed.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: document.fields.compactMap { field in
            guard !field.readOnly, let key = field.key, let value = previous.values[key], accepts(value, for: field) else { return nil }
            return (field.id, value)
        })
    }

    private func accepts(_ value: String, for field: NativeServiceDocument.Field) -> Bool {
        guard value.count <= 100_000 else { return false }
        if ["checkbox", "toggle"].contains(field.kind) { return ["true", "false"].contains(value) }
        if ["select", "radio", "choice"].contains(field.kind) { return field.options.contains { $0.value == value } }
        if field.kind == "multiselect" {
            guard let data = value.data(using: .utf8), let values = try? JSONDecoder().decode([String].self, from: data),
                  Set(values).count == values.count else { return false }
            return values.allSatisfy { value in field.options.contains { $0.value == value } }
        }
        return ["text", "textarea", "number", "email", "tel", "url", "search", "date", "time", "datetime-local"].contains(field.kind)
    }

    private func signature(_ document: NativeServiceDocument) -> Data? {
        guard let identity = document.draftIdentity, !identity.isEmpty else { return nil }
        let fields: [[String: Any]] = document.fields.map { field in
            ["key": field.key ?? "", "label": field.label, "kind": field.kind, "value": field.value,
             "required": field.required, "readOnly": field.readOnly,
             "commit": field.commit ?? "", "queryField": field.queryField ?? false, "multiple": field.multiple ?? false,
             "options": field.options.map { ["value": $0.value, "title": $0.title, "selected": $0.selected.map { String($0) } ?? "unknown"] }]
        }
        let tables: [[String: Any]] = document.tables.map {
            ["title": $0.title, "headers": $0.headers, "rows": $0.rows, "truncated": $0.truncated]
        }
        return try? JSONSerialization.data(withJSONObject: ["identity": identity, "title": document.title, "fields": fields, "tables": tables], options: [.sortedKeys])
    }
}
