// 다마고치 기능(플러그인) — 클릭했을 때 열리는 패널 + 알려 줄 일이 있으면 말풍선.
// 새 기능을 넣는 방법은 docs/EXTENDING.md 를 보세요.
import AppKit
import SwiftUI

protocol PetFeature: AnyObject {
    /// pet.json 의 "features" 에 적는 이름 (예: "calendar")
    static var id: String { get }
    /// 패널 탭에 보일 이름
    var title: String { get }
    /// 데이터를 새로 가져온다. 패널을 열 때와 refreshInterval 마다 불린다. (메인 스레드에서 불림 — 오래 걸리는 일은 백그라운드로)
    func refresh()
    /// 몇 초마다 refresh 할지
    var refreshInterval: TimeInterval { get }
    /// 다마고치가 말풍선으로 알려 줄 말. 새로 알릴 게 있을 때만 값이 있고, 한 번 말하면 다시 nil 이 되게 만든다.
    func takeAttention() -> String?
    /// 클릭하면 열리는 패널 화면
    func makePanel() -> AnyView
    /// 머리 위 알림 말풍선(❗)에 띄울 짧은 글 — 예: 확인 안 한 개수 "3", 남은 양 "5%". 없으면 nil. (선택)
    var badge: String? { get }
    /// 패널을 열었을 때 불림 — 「확인했음」 처리해서 badge 를 지우는 곳. (선택)
    func markSeen()
}

extension PetFeature {
    var badge: String? { nil }
    func markSeen() {}
}

/// 기능 목록: 이름 → 만드는 방법. 새 기능을 만들면 여기에 한 줄 추가한다.
let featureRegistry: [String: () -> PetFeature] = [
    CalendarFeature.id: { CalendarFeature() },
    AIUsageFeature.id: { AIUsageFeature() },
    GmailFeature.id: { GmailFeature() },
]

/// 패널: 기능이 하나면 그대로, 여러 개면 탭으로
struct FeaturesPanel: View {
    let features: [PetFeature]
    // 확인용 인자 --panel-tab N : 패널을 N번째 탭으로 연다
    @State private var tab = CommandLine.arguments.firstIndex(of: "--panel-tab")
        .flatMap { i in CommandLine.arguments.indices.contains(i + 1) ? Int(CommandLine.arguments[i + 1]) : nil } ?? 0

    var body: some View {
        VStack(spacing: 8) {
            if features.count > 1 {
                Picker("", selection: $tab) {
                    ForEach(features.indices, id: \.self) { Text(features[$0].title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14).padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)      // 탭 버튼은 어떤 기능 화면에서도 밀려나지 않게
            }
            if features.indices.contains(tab) {
                // 기능 화면은 남은 공간 안에서만 그린다 (넘치면 잘림, 탭을 밀어내지 않음)
                features[tab].makePanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .id(tab)
            }
        }
        .frame(width: 340, height: 480)
    }
}
