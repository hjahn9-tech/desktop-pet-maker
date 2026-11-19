import SwiftUI

private func resetText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = Calendar.current.isDateInToday(d) ? "오늘 HH:mm" : "M/d(E) HH:mm"
    return f.string(from: d) + " 리셋"
}

private func agoText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let s = Int(Date().timeIntervalSince(d))
    if s < 90 { return "방금" }
    if s < 3600 { return "\(s / 60)분 전" }
    if s < 86400 { return "\(s / 3600)시간 전" }
    return "\(s / 86400)일 전"
}

private func elapsedText(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let s = Int(Date().timeIntervalSince(d))
    if s < 3600 { return "\(max(1, s / 60))분째" }
    if s < 86400 { return "\(s / 3600)시간째" }
    return "\(s / 86400)일째"
}

struct UsageBar: View {
    let w: UsageWindow
    var color: Color { w.remaining > 50 ? .green : (w.remaining > 20 ? .orange : .red) }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(w.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(resetText(w.resetsAt)).font(.caption2).foregroundStyle(.secondary)
                Text("\(Int(w.remaining.rounded()))% 남음").font(.caption.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: max(4, g.size.width * w.remaining / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

struct AIUsagePanelView: View {
    @ObservedObject var store: AIUsageStore

    var grouped: [(String, [AgentSession])] {
        var order: [String] = []
        var map: [String: [AgentSession]] = [:]
        for s in store.sessions {
            if map[s.service] == nil { order.append(s.service) }
            map[s.service, default: []].append(s)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI 에이전트").font(.headline)
                Spacer()
                if store.loadingUsage { ProgressView().controlSize(.small) }
                Button {
                    store.refreshSessions()
                    store.refreshUsage()
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("새로 고침")
            }

            Text("사용량").font(.subheadline.weight(.semibold))
            ForEach(store.usages) { u in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(u.id).font(.callout.weight(.medium))
                        Spacer()
                        if u.id == "Codex", u.asOf != nil {
                            Text(agoText(u.asOf) + " 기록").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(u.windows) { UsageBar(w: $0) }
                    if let n = u.note, u.windows.isEmpty || u.id != "Codex" {
                        Text(n).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            Divider()
            Text("실행 중인 세션 \(store.sessions.count)개").font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.sessions.isEmpty {
                        Text("실행 중인 에이전트 세션이 없습니다").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(grouped, id: \.0) { service, list in
                        Text("\(service) · \(list.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(list) { s in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(s.busy == true ? Color.orange : (s.busy == false ? Color.green : Color.gray))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.callout).lineLimit(1)
                                    Text(tildePath(s.cwd)).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(s.busy == true ? "작업 중" : (s.busy == false ? "대기" : "실행 중")).font(.caption)
                                    Text(elapsedText(s.started)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)   // 패널 크기는 FeaturesPanel 이 정함
    }
}
