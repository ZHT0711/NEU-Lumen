import Foundation

struct PersonalAcademicProgram: Identifiable, Equatable {
    let id: String
    let name: String
    let minimumCredits: String?
    let facts: [ProgramFact]
}

struct ProgramFact: Identifiable, Equatable {
    let title: String
    let value: String
    var id: String { title }
}

struct AcademicProgramNode: Identifiable, Equatable {
    let id: String
    let parentID: String?
    let name: String
    let minimumCredits: String?
    let minimumGroups: String?
    let kind: String
    let inherited: Bool
    let referenced: Bool
    let mustPass: Bool
}

struct AcademicProgramTree: Equatable {
    let program: PersonalAcademicProgram
    let nodes: [AcademicProgramNode]
    func children(of id: String) -> [AcademicProgramNode] { nodes.filter { $0.parentID == id } }
}

enum PersonalAcademicProgramParser {
    static func rows(_ raw: Any, action: String) throws -> (rows: [[String: Any]], total: Int?) {
        let payload = try AcademicQueryParser.payload(raw, title: "个人培养方案")
        guard let datas = payload as? [String: Any], let result = datas[action] as? [String: Any],
              let rows = result["rows"] as? [[String: Any]], rows.count <= 1000 else {
            throw AcademicQueryError.invalid("个人培养方案" )
        }
        let total = AcademicQueryParser.scalar(result["totalSize"]).flatMap(Int.init)
        if let total, total < 0 || total > 10000 { throw AcademicQueryError.invalid("培养方案分页") }
        return (rows, total)
    }

    static func program(_ row: [String: Any]) throws -> PersonalAcademicProgram {
        guard let id = AcademicQueryParser.scalar(row["PYFADM"]), let name = AcademicQueryParser.scalar(row["PYFAMC"]) else {
            throw AcademicQueryError.invalid("个人培养方案")
        }
        let fields = [("年级", "NJDM_DISPLAY"), ("院系", "DWDM_DISPLAY"), ("专业", "ZYDM_DISPLAY"),
                      ("专业方向", "ZYFXDM_DISPLAY"), ("方案类型", "FALXDM_DISPLAY"), ("修读类型", "XDLXDM_DISPLAY"),
                      ("培养层次", "PYCCDM_DISPLAY"), ("审核状态", "SHZTDM_DISPLAY")]
        return PersonalAcademicProgram(id: id, name: name, minimumCredits: AcademicQueryParser.scalar(row["ZSYQXF"]),
            facts: fields.compactMap { title, key in AcademicQueryParser.scalar(row[key]).map { ProgramFact(title: title, value: $0) } })
    }

    static func tree(program: PersonalAcademicProgram, groups: [[String: Any]]) throws -> AcademicProgramTree {
        var nodes = [AcademicProgramNode(id: program.id, parentID: nil, name: program.name, minimumCredits: program.minimumCredits,
            minimumGroups: nil, kind: "培养方案", inherited: false, referenced: false, mustPass: false)]
        var seen: Set<String> = [program.id]
        for row in groups {
            guard AcademicQueryParser.scalar(row["PYFADM"]) == program.id,
                  let id = AcademicQueryParser.scalar(row["KZH"]), seen.insert(id).inserted,
                  let parent = AcademicQueryParser.scalar(row["FKZH"]), let name = AcademicQueryParser.scalar(row["KZM"]) else {
                throw AcademicQueryError.invalid("培养方案课组层级")
            }
            let source = AcademicQueryParser.scalar(row["GGKZLY"])
            let shared = AcademicQueryParser.scalar(row["ISTKZ"]) == "1"
            nodes.append(AcademicProgramNode(id: id, parentID: parent == "-1" ? program.id : parent, name: name,
                minimumCredits: AcademicQueryParser.scalar(row["ZSXDXF"]), minimumGroups: AcademicQueryParser.scalar(row["ZSWCKZS"]),
                kind: AcademicQueryParser.scalar(row["KZLXDM"]) == "02" ? "平台" : "课组",
                inherited: shared && source == "03", referenced: shared && source == "02",
                mustPass: AcademicQueryParser.scalar(row["SFBG"]) == "1"))
        }
        let parents = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.parentID) })
        for node in nodes {
            var path = Set<String>(), cursor: String? = node.id
            while let id = cursor {
                guard path.insert(id).inserted, seen.contains(id), path.count <= 50 else { throw AcademicQueryError.invalid("培养方案课组层级") }
                cursor = parents[id] ?? nil
            }
        }
        return AcademicProgramTree(program: program, nodes: nodes)
    }

    static func course(_ row: [String: Any], index: Int) throws -> AcademicPageCourse {
        guard let name = AcademicQueryParser.scalar(row["KCM"]) else { throw AcademicQueryError.invalid("课组课程") }
        return AcademicPageCourse(id: String(index), name: name, code: AcademicQueryParser.scalar(row["KCH"]),
            creditsText: AcademicQueryParser.scalar(row["XF"]), module: AcademicQueryParser.scalar(row["KZM"]), studyStatus: nil,
            suggestedTerm: AcademicQueryParser.scalar(row["XDXQ"]) ?? AcademicQueryParser.scalar(row["XNXQ_DISPLAY"]),
            category: AcademicQueryParser.scalar(row["KCXZDM_DISPLAY"]), hoursText: AcademicQueryParser.scalar(row["NEWXS"]),
            assessment: AcademicQueryParser.scalar(row["KSLXDM_DISPLAY"]))
    }
}

/// Deterministic branch layout, retaining the school's parent IDs and sibling order.
struct AcademicProgramLayout {
    struct Item: Identifiable {
        let node: AcademicProgramNode
        let depth: Int
        let y: Double
        var id: String { node.id }
    }
    let items: [Item]
    let height: Double
    let columns: Int
    init(tree: AcademicProgramTree, collapsed: Set<String>, query: String) {
        let children = Dictionary(grouping: tree.nodes.filter { $0.parentID != nil }, by: { $0.parentID! })
        let parents = Dictionary(uniqueKeysWithValues: tree.nodes.map { ($0.id, $0.parentID) })
        var included = Set<String>()
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            for node in tree.nodes where node.name.localizedCaseInsensitiveContains(key) {
                var cursor: String? = node.id
                while let id = cursor, included.insert(id).inserted { cursor = parents[id] ?? nil }
            }
        }
        var output: [Item] = [], row = 0.0
        func place(_ node: AcademicProgramNode, depth: Int) -> Double {
            let branches = (children[node.id] ?? []).filter { key.isEmpty || included.contains($0.id) }
            let y: Double
            if branches.isEmpty || (key.isEmpty && collapsed.contains(node.id)) { y = row * 126 + 60; row += 1 }
            else {
                let centers = branches.map { place($0, depth: depth + 1) }
                y = (centers.first! + centers.last!) / 2
            }
            output.append(Item(node: node, depth: depth, y: y))
            return y
        }
        if let root = tree.nodes.first, key.isEmpty || included.contains(root.id) { _ = place(root, depth: 0) }
        items = output; height = max(126, row * 126); columns = (output.map(\.depth).max() ?? 0) + 1
    }
}
