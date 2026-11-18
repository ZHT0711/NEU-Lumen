import SwiftUI

struct CampusWidgetSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section {
                Toggle("显示个人课表和作业", isOn: Binding(
                    get: { environment.repository.widgetSharingEnabled },
                    set: { environment.repository.setWidgetSharingEnabled($0) }
                ))
                .disabled(!CampusWidgetSnapshot.isSharingAvailable)
                if let error = environment.repository.widgetSharingError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                if CampusWidgetSnapshot.isSharingAvailable {
                    Text("打开应用并加载课表或作业后，小组件会读取本机摘要。锁屏上的显示受系统隐私设置控制。")
                } else {
                    Text("当前安装签名没有小组件共享权限。你仍可以添加「校园入口」，从桌面打开校园服务。")
                }
            }

            Section("添加小组件") {
                Text("长按主屏幕空白处，选择编辑和添加小组件，搜索 NEU-Lumen。锁屏编辑器也可以添加「下一节课」。")
            }
        }
        .navigationTitle("小组件")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await environment.repository.ensureLoadedForCurrentUser()
        }
    }
}
