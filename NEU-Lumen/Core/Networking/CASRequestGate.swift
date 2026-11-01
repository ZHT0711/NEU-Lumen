/// CAS 换票逐项完成，避免一卡通、网费、电费并发改写同一认证会话。
actor CASRequestGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
}
