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
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 8) {
            if features.count > 1 {
                Picker("", selection: $tab) {
                    ForEach(features.indices, id: \.self) { Text(features[$0].title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14).padding(.top, 12)
            }
            if features.indices.contains(tab) {
                features[tab].makePanel()
                    .id(tab)
            }
        }
        .frame(width: 340, height: 480)
    }
}
