// 기능 예시 ②: 오늘 일정 — macOS 캘린더 앱에 연결된 모든 계정(구글·iCloud·회사 계정 등)
// 구글 캘린더는 「시스템 설정 › 인터넷 계정 › Google」에서 캘린더를 켜 두면 여기에 보입니다. 따로 키가 필요 없습니다.
import EventKit
import SwiftUI

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let calendar: String
    let color: Color
}

final class CalendarModel: ObservableObject {
    @Published var events: [DayEvent] = []
    @Published var denied = false
    let ek = EKEventStore()
    private var asked = false

    func refresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined && !asked {
            asked = true
            let done: (Bool, Error?) -> Void = { [weak self] ok, _ in
                DispatchQueue.main.async { self?.denied = !ok; if ok { self?.refresh() } }
            }
            if #available(macOS 14.0, *) { ek.requestFullAccessToEvents(completion: done) }
            else { ek.requestAccess(to: .event, completion: done) }
            return
        }
        var ok = status == .authorized
        if #available(macOS 14.0, *) { ok = ok || status == .fullAccess }
        denied = !ok
        guard ok else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        events = ek.events(matching: ek.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.status != .canceled }
            .map { e in
                DayEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                         title: e.title?.isEmpty == false ? e.title! : "(제목 없음)",
                         start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                         location: e.location?.isEmpty == false ? e.location : nil,
                         calendar: e.calendar.title, color: Color(nsColor: e.calendar.color ?? .systemBlue))
            }
            .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }
}

final class CalendarFeature: PetFeature {
    static let id = "calendar"
    let title = "오늘 일정"
    let refreshInterval: TimeInterval = 300
    let model = CalendarModel()
    private var told = Set<String>()

    init() { refresh() }
    func refresh() { model.refresh() }

    /// 10분 안에 시작하는 일정을 한 번씩 알려 준다
    func takeAttention() -> String? {
        for e in model.events where !e.allDay && !told.contains(e.id) {
            let m = e.start.timeIntervalSinceNow / 60
            if m > 0 && m <= 10 {
                told.insert(e.id)
                return "\(Int(m.rounded(.up)))분 뒤: \(e.title)"
            }
        }
        return nil
    }

    func makePanel() -> AnyView { AnyView(CalendarPanel(model: model)) }
}

struct CalendarPanel: View {
    @ObservedObject var model: CalendarModel

    private func hm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오늘 일정").font(.headline)
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            if model.denied {
                Text("캘린더 접근이 꺼져 있습니다. 시스템 설정 › 개인정보 보호 및 보안 › 캘린더에서 이 앱을 켜 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.events.isEmpty && !model.denied {
                        Text("오늘 일정이 없습니다").foregroundStyle(.secondary)
                    }
                    ForEach(model.events) { e in
                        HStack(alignment: .top, spacing: 8) {
                            Text(e.allDay ? "종일" : hm(e.start)).font(.callout.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(.callout.weight(.medium))
                                if let l = e.location { Text(l).font(.caption).foregroundStyle(.secondary) }
                                Text(e.calendar).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .opacity(!e.allDay && e.end < Date() ? 0.45 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }
}
