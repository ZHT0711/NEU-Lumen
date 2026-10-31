import Foundation

/// 页面加载状态。
enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
