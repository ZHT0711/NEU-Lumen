/// CAS 换票逐项完成，避免一卡通、网费、电费并发改写同一认证会话。
actor CASRequestGate {
    private let limit: Int
    private var active = 0
    init(limit: Int = 1) { self.limit = max(1, limit) }
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active -= 1 }
        else { waiters.removeFirst().resume() }
    }
}
