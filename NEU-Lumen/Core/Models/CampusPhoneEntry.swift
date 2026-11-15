import Foundation

struct CampusPhoneEntry: Identifiable {
    let department: String
    let office: String
    let phone: String
    let address: String
    var id: String { [department, office, phone, address].joined(separator: "|") }

    init?(cells: [String]) {
        guard cells.count == 4, cells[0] != "部门名称" else { return nil }
        department = cells[0]
        office = cells[1]
        phone = cells[2]
        address = cells[3]
    }

    var dialNumbers: [String] {
        var seen = Set<String>()
        return phone.components(separatedBy: CharacterSet(charactersIn: "/、，,;；\n")).compactMap { part in
            guard !part.contains("传真") else { return nil }
            let digits = part.filter(\.isASCII).filter(\.isNumber)
            guard (8...13).contains(digits.count) else { return nil }
            let number = digits.count == 8 ? "024" + digits : digits
            return seen.insert(number).inserted ? number : nil
        }
    }

    var shareText: String { [department, office, phone, address].filter { !$0.isEmpty }.joined(separator: "\n") }
}
