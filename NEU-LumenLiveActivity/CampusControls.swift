import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NEULumenScheduleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "edu.neu.lumen.control.today-schedule") {
            ControlWidgetButton(action: OpenCampusPageIntent(target: .todaySchedule)) {
                Label("今日课表", systemImage: "calendar")
                    .controlWidgetActionHint(Text("打开今日课表"))
            }
        }
        .displayName("今日课表")
        .description("打开今天的课程安排。")
    }
}

@available(iOS 18.0, *)
struct NEULumenCampusMapControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "edu.neu.lumen.control.campus-map") {
            ControlWidgetButton(action: OpenCampusPageIntent(target: .map)) {
                Label("校园地图", systemImage: "map")
                    .controlWidgetActionHint(Text("打开校园地图"))
            }
        }
        .displayName("校园地图")
        .description("打开校园地图，查找建筑和入口。")
    }
}
