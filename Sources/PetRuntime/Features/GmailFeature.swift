// 기능 예시 ③: 지메일 — 받은편지함의 안 읽은 메일 (읽기 전용)
// 준비: tools/google_login.py 로 한 번 로그인하면 ~/.config/desktop-pet/google_token.json 이 생긴다.
//       (구글 클라우드에서 만든 내 OAuth 클라이언트 credentials.json 이 필요 — docs/EXTENDING.md 참고)
import AppKit
import SwiftUI

struct MailItem: Identifiable {
    let id: String
    let thread: String
    let from: String
    let subject: String
    let snippet: String
    let date: Date
}

enum GoogleAuth {
    static let tokenPath = NSHomeDirectory() + "/.config/desktop-pet/google_token.json"
    private static var cached: (String, Date)?

    static func send(_ req: URLRequest) -> (Int, Data?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Int, Data?) = (0, nil)
        URLSession.shared.dataTask(with: req) { d, r, _ in
            out = ((r as? HTTPURLResponse)?.statusCode ?? 0, d); sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    /// 저장된 refresh_token 으로 access token 받기 (만료 2분 전까지 재사용)
    static func accessToken() -> String? {
        if let (t, exp) = cached, Date() < exp { return t }
        guard let d = FileManager.default.contents(atPath: tokenPath),
              let c = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let id = c["client_id"] as? String, let secret = c["client_secret"] as? String,
              let refresh = c["refresh_token"] as? String else { return nil }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var q = URLComponents()
        q.queryItems = [.init(name: "client_id", value: id), .init(name: "client_secret", value: secret),
                        .init(name: "refresh_token", value: refresh), .init(name: "grant_type", value: "refresh_token")]
        req.httpBody = q.percentEncodedQuery?.data(using: .utf8)
        let (code, data) = send(req)
        guard code == 200, let data = data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = o["access_token"] as? String else { return nil }
        cached = (t, Date().addingTimeInterval(((o["expires_in"] as? Double) ?? 3600) - 120))
        return t
    }
}

final class MailModel: ObservableObject {
    @Published var items: [MailItem] = []
    @Published var unread: Int?
    @Published var account: String?
    @Published var note: String?
    @Published var loading = false
    var seen = Set<String>()      // 패널에서 확인한 메일 (❗ 숫자 기준)
    var told = Set<String>()      // 말풍선으로 이미 알린 메일
    var first = true
    var fresh: [MailItem] = []    // 아직 말풍선으로 안 알린 새 메일
    /// 패널을 마지막으로 연 뒤 새로 온 메일 수
    @Published var newCount = 0
    private let q = DispatchQueue(label: "desktoppet.gmail", qos: .utility)

    func refresh() {
        loading = true
        q.async {
            let r = Self.fetch()
            DispatchQueue.main.async {
                self.loading = false
                self.items = r.items; self.unread = r.unread; self.account = r.account; self.note = r.note
                guard r.note == nil else { return }   // 읽기 실패면 새 메일 계산을 건드리지 않음
                let ids = Set(r.items.map { $0.id })
                if self.first { self.seen = ids; self.told = ids; self.first = false }
                self.fresh = r.items.filter { !self.told.contains($0.id) }
                self.newCount = ids.subtracting(self.seen).count
            }
        }
    }

    static func fetch() -> (items: [MailItem], unread: Int?, account: String?, note: String?) {
        guard FileManager.default.fileExists(atPath: GoogleAuth.tokenPath) else {
            return ([], nil, nil, "아직 연결 안 됨 — tools/google_login.py 로 로그인해 주세요")
        }
        guard let t = GoogleAuth.accessToken() else { return ([], nil, nil, "구글 로그인이 만료됐습니다. 다시 로그인해 주세요") }
        func get(_ path: String, _ qi: [URLQueryItem] = []) -> (Int, [String: Any]?) {
            var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
            if !qi.isEmpty { c.queryItems = qi }
            var req = URLRequest(url: c.url!)
            req.timeoutInterval = 15
            req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
            let (code, d) = GoogleAuth.send(req)
            return (code, d.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] })
        }
        let (pc, prof) = get("profile")
        guard pc == 200 else { return ([], nil, nil, "메일을 읽지 못했습니다 (HTTP \(pc))") }
        let unread = get("labels/INBOX").1?["messagesUnread"] as? Int
        let ids = ((get("messages", [.init(name: "q", value: "in:inbox is:unread"), .init(name: "maxResults", value: "15")])
            .1?["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        var slots = [MailItem?](repeating: nil, count: ids.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: ids.count) { k in
            guard let m = get("messages/\(ids[k])", [.init(name: "format", value: "metadata"),
                                                     .init(name: "metadataHeaders", value: "From"),
                                                     .init(name: "metadataHeaders", value: "Subject")]).1 else { return }
            var from = "", subject = ""
            for h in ((m["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? [] {
                let v = h["value"] as? String ?? ""
                if (h["name"] as? String)?.lowercased() == "from" { from = v }
                if (h["name"] as? String)?.lowercased() == "subject" { subject = v }
            }
            if let lt = from.firstIndex(of: "<") {
                let n = from[..<lt].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !n.isEmpty { from = n }
            }
            let item = MailItem(id: ids[k], thread: m["threadId"] as? String ?? ids[k], from: from,
                                subject: subject.isEmpty ? "(제목 없음)" : subject,
                                snippet: (m["snippet"] as? String ?? "").replacingOccurrences(of: "&#39;", with: "'")
                                    .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&"),
                                date: Date(timeIntervalSince1970: (Double(m["internalDate"] as? String ?? "") ?? 0) / 1000))
            lock.lock(); slots[k] = item; lock.unlock()
        }
        return (slots.compactMap { $0 }, unread, prof?["emailAddress"] as? String, nil)
    }

    func open(_ m: MailItem) {
        let u = account ?? "0"
        if let url = URL(string: "https://mail.google.com/mail/u/?authuser=\(u)#inbox/\(m.thread)") { NSWorkspace.shared.open(url) }
    }
}

final class GmailFeature: PetFeature {
    static let id = "gmail"
    let title = "메일"
    let refreshInterval: TimeInterval = 120
    let model = MailModel()

    init() { refresh() }
    func refresh() { model.refresh() }

    func takeAttention() -> String? {
        guard let m = model.fresh.first else { return nil }
        model.told.formUnion(model.fresh.map { $0.id })
        let more = model.fresh.count > 1 ? " 외 \(model.fresh.count - 1)통" : ""
        model.fresh = []
        return "새 메일: \(m.from)\(more)"
    }

    func makePanel() -> AnyView { AnyView(MailPanel(model: model)) }

    /// ❗ 확인 안 한 새 메일 수
    var badge: String? { model.newCount > 0 ? "\(model.newCount)" : nil }
    func markSeen() {
        model.seen.formUnion(model.items.map { $0.id })
        model.told.formUnion(model.items.map { $0.id })
        model.newCount = 0
    }
}

struct MailPanel: View {
    @ObservedObject var model: MailModel

    private func when(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "M/d"; return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("메일").font(.headline)
                if let n = model.unread { Text("안 읽음 \(n)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            if let n = model.note { Text(n).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.items.isEmpty && model.note == nil {
                        Text(model.loading ? "불러오는 중…" : "안 읽은 메일이 없습니다").foregroundStyle(.secondary)
                    }
                    ForEach(model.items) { m in
                        Button { model.open(m) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(m.from).font(.callout.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text(when(m.date)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(m.subject).font(.callout).lineLimit(1)
                                Text(m.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
    }
}
