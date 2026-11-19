// 기능 예시 ①: AI 에이전트 세션·사용량 (Claude Code · Codex)
//  - 실행 중인 세션: ~/.claude/sessions, 실행 중 프로세스, ~/.codex/sessions 를 읽음
//  - Claude Code 사용량: Claude Code 로그인 토큰(키체인)으로 /api/oauth/usage 를 조회 — 공식 공개 API가 아니라 바뀔 수 있음
//  - Codex 사용량: 로컬 세션 기록의 마지막 rate_limits
import SwiftUI

final class AIUsageFeature: PetFeature {
    static let id = "ai-usage"
    let title = "AI 사용량"
    let refreshInterval: TimeInterval = 120
    let store = AIUsageStore()
    private var warned = false

    init() { refresh() }

    func refresh() {
        store.refreshSessions()
        store.refreshUsage()
    }

    func takeAttention() -> String? {
        guard let low = store.lowestWeeklyRemaining else { return nil }
        if low < 15 && !warned {
            warned = true
            return "주간 사용량이 \(Int(low))%밖에 안 남았어요!"
        }
        if low >= 15 { warned = false }
        return nil
    }

    func makePanel() -> AnyView { AnyView(AIUsagePanelView(store: store)) }
}
