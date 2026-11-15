import Foundation

enum PortalClient { static let portalBase = "https://personal.neu.edu.cn/portal" }

@main struct NativeCampusToolsTests {
    @MainActor static func main() {
        func grade(_ score: Double?, _ text: String = "", credit: Double = 2) -> GradeCourse {
            GradeCourse(name: "synthetic", credit: credit, category: "", score: score, scoreRaw: text)
        }
        let courses = [grade(90), grade(50), grade(nil, "优秀"), grade(nil, "缓考"), grade(nil, "85"), grade(.infinity), grade(80, credit: -1)]
        let stats = GradeAnalysis(courses: courses)
        precondition(stats.scored.count == 5 && stats.failed.count == 1 && stats.statusRecords.count == 2)
        precondition(stats.gradedCredits == 8 && stats.passedCredits == 6)
        precondition(stats.weightedAverage == 80)
        precondition(stats.bands.reduce(0) { $0 + $1.count } == 5)
        precondition(grade(nil, "0").hasScore && grade(nil, "0").normalizedScore == 0)
        precondition(grade(nil, " 优秀\n").normalizedScore == 95)
        precondition(!grade(nil, "缓考").hasScore && !grade(101).hasScore && !grade(.nan).hasScore)
        precondition(grade(.infinity).scoreText == "暂无")
        let semester = GradeSemester(name: "synthetic", termCode: "1", current: true, courses: courses)
        precondition(semester.weightedAvg == 80 && semester.credits == 8)
        precondition(GradeAnalysis(courses: []).weightedAverage == nil)

        let phone = CampusPhoneEntry(cells: ["合成部门", "合成办公室", "00000000/00000001（传真）", "合成地址"])!
        precondition(phone.dialNumbers == ["02400000000"])
        precondition(CampusPhoneEntry(cells: ["部门名称", "办公室名称", "办公电话", "办公地址"]) == nil)
        precondition(CampusPhoneEntry(cells: ["incomplete"]) == nil)
        precondition(NativeCampusService.telephone.allowsNativeDocument(URL(string: "https://plat.neu.edu.cn/telephone-directory/home")!))
        precondition(!NativeCampusService.telephone.allowsNativeDocument(URL(string: "https://plat.neu.edu.cn.evil.example/")!))
        precondition(NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8991/F/-?func=find-b-0")!))
        precondition(!NativeCampusService.payment.allowsNativeDocument(URL(string: "http://pay.neu.edu.cn/")!))
        precondition(!NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8992/F/")!))
        precondition(!NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8991/other")!))

        let rooms = ElectricRoomKey.recentRooms(selecting: "１２３-４５６７", in: ["1234567", "2345678", "3456789", "invalid", "4567890", "5678901", "6789012"])
        precondition(rooms == ["1234567", "2345678", "3456789", "4567890", "5678901"])

        let suite = "NEULumen.NativeNews.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedCampusNews(defaults: defaults)
        let item = NewsItem(id: "synthetic", title: "合成资讯", date: "2026-01-01", category: "合成频道", url: "https://neunews.neu.edu.cn/synthetic", picUrl: "")
        saved.bind(account: "A")
        saved.toggle(item)
        precondition(saved.items == [item])
        saved.bind(account: "B")
        precondition(saved.items.isEmpty)
        saved.bind(account: "A")
        precondition(saved.items == [item])
        let restored = SavedCampusNews(defaults: defaults)
        restored.bind(account: "A")
        precondition(restored.items == [item])
        restored.toggle(item)
        precondition(restored.items.isEmpty)
        saved.bind(account: nil)
        saved.toggle(item)
        precondition(saved.items.isEmpty)
        print("PASS: native grade analysis, pending states, nonfinite/zero scores, phone rows, library host/port bounds, room history and saved-news account persistence")
    }
}
