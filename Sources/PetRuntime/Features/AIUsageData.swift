import Foundation
import Darwin

// MARK: - 모델

struct AgentSession: Identifiable {
    let id: String
    let service: String
    let title: String
    let cwd: String
    let busy: Bool?          // nil = 알 수 없음
    let started: Date?
}

struct UsageWindow: Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    var remaining: Double { max(0, min(100, 100 - usedPercent)) }
}

struct ServiceUsage: Identifiable {
    let id: String           // 서비스 이름
    var windows: [UsageWindow] = []
    var note: String? = nil
    var asOf: Date? = nil
}

// MARK: - 공용 도우미

func runTool(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
}

func cwd(of pid: Int32) -> String? {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
}

func tildePath(_ p: String) -> String {
    let home = NSHomeDirectory()
    return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}

/// ps 의 etime([[dd-]hh:]mm:ss) → 시작 시각
func startDate(etime: String) -> Date? {
    var days = 0.0
    var rest = Substring(etime)
    if let dash = etime.firstIndex(of: "-") {
        days = Double(etime[..<dash]) ?? 0
        rest = etime[etime.index(after: dash)...]
    }
    let parts = rest.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }
    var secs = 0.0
    for v in parts { secs = secs * 60 + v }
    return Date().addingTimeInterval(-(days * 86400 + secs))
}

// MARK: - 세션 수집

enum SessionScanner {
    static let home = NSHomeDirectory()
    /// 프로세스 이름으로 찾는 그 밖의 에이전트 CLI
    static let otherCLIs: [String: String] = [
        "gemini": "Gemini CLI", "aider": "Aider", "opencode": "opencode", "cursor-agent": "Cursor Agent",
    ]

    static func scan() -> [AgentSession] {
        var result = claudeSessions()
        let procs = processes()
        var codexCwds = Set<String>()

        for p in procs {
            let tokens = p.command.split(separator: " ").prefix(2).map { ($0 as NSString).lastPathComponent }
            guard let first = tokens.first else { continue }
            if first == "codex" {
                if p.command.contains("app-server") { continue }
                let dir = cwd(of: p.pid) ?? ""
                codexCwds.insert(dir)
                result.append(AgentSession(id: "codex-\(p.pid)", service: "Codex",
                                           title: dir.isEmpty ? "codex" : (dir as NSString).lastPathComponent,
                                           cwd: dir, busy: nil, started: p.started))
            } else if let name = tokens.compactMap({ otherCLIs[$0] }).first {
                let dir = cwd(of: p.pid) ?? ""
                result.append(AgentSession(id: "\(name)-\(p.pid)", service: name,
                                           title: dir.isEmpty ? name : (dir as NSString).lastPathComponent,
                                           cwd: dir, busy: nil, started: p.started))
            }
        }
        // Codex 앱·IDE 스레드: 최근 10분 안에 기록이 갱신된 것
        for f in CodexFiles.recent(limit: 12) where Date().timeIntervalSince(f.mtime) < 600 {
            let dir = CodexFiles.cwd(of: f.url) ?? ""
            if codexCwds.contains(dir) { continue }
            result.append(AgentSession(id: "codex-thread-\(f.url.lastPathComponent)", service: "Codex",
                                       title: dir.isEmpty ? "Codex 스레드" : (dir as NSString).lastPathComponent,
                                       cwd: dir, busy: Date().timeIntervalSince(f.mtime) < 60, started: nil))
        }
        return result
    }

    static func claudeSessions() -> [AgentSession] {
        let dir = URL(fileURLWithPath: home + "/.claude/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [AgentSession] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = o["pid"] as? Int, kill(Int32(pid), 0) == 0 || errno == EPERM else { continue }
            let dirPath = o["cwd"] as? String ?? ""
            let name = o["name"] as? String ?? (dirPath as NSString).lastPathComponent
            let status = o["status"] as? String
            let started = (o["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            out.append(AgentSession(id: "claude-\(pid)", service: "Claude Code", title: name, cwd: dirPath,
                                    busy: status.map { $0 == "busy" }, started: started))
        }
        return out.sorted { ($0.started ?? .distantPast) > ($1.started ?? .distantPast) }
    }

    struct Proc { let pid: Int32; let started: Date?; let command: String }

    static func processes() -> [Proc] {
        guard let text = runTool("/bin/ps", ["-axo", "pid=,etime=,command="]) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]) else { return nil }
            return Proc(pid: pid, started: startDate(etime: String(parts[1])), command: String(parts[2]))
        }
    }
}

// MARK: - Codex 로컬 기록

enum CodexFiles {
    struct Entry { let url: URL; let mtime: Date }

    static func recent(limit: Int) -> [Entry] {
        let root = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/sessions")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var all: [Entry] = []
        for case let u as URL in en where u.pathExtension == "jsonl" {
            if let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                all.append(Entry(url: u, mtime: m))
            }
        }
        return Array(all.sorted { $0.mtime > $1.mtime }.prefix(limit))
    }

    static func cwd(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let head = String(decoding: h.readData(ofLength: 4096), as: UTF8.self)
        guard let r = head.range(of: "\"cwd\":\"") else { return nil }
        let rest = head[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// 파일 끝부분에서 마지막 rate_limits 객체를 꺼낸다
    static func lastRateLimits(in url: URL) -> [String: Any]? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let chunk: UInt64 = 400_000
        try? h.seek(toOffset: size > chunk ? size - chunk : 0)
        let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        guard let r = text.range(of: "\"rate_limits\":{", options: .backwards) else { return nil }
        var depth = 0
        var end: String.Index?
        var i = text.index(before: r.upperBound)
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { end = i; break } }
            i = text.index(after: i)
        }
        guard let e = end else { return nil }
        let json = String(text[text.index(before: r.upperBound)...e])
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }
}

// MARK: - 사용량

enum UsageFetcher {
    static func windowLabel(minutes: Double) -> String {
        if minutes >= 10080 { return "주간" }
        if minutes >= 1440 { return "\(Int(minutes / 1440))일" }
        return "\(Int(minutes / 60))시간"
    }

    static func codex() -> ServiceUsage {
        var u = ServiceUsage(id: "Codex")
        for f in CodexFiles.recent(limit: 15) {
            guard let rl = CodexFiles.lastRateLimits(in: f.url) else { continue }
            for key in ["primary", "secondary"] {
                guard let w = rl[key] as? [String: Any], let used = w["used_percent"] as? Double else { continue }
                let mins = (w["window_minutes"] as? Double) ?? 0
                let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                // 리셋 시각이 지났으면 그 뒤로 쓴 기록이 없다는 뜻 → 전부 남음
                let passed = reset.map { $0 < Date() } ?? false
                u.windows.append(UsageWindow(id: "codex-\(key)", label: windowLabel(minutes: mins),
                                             usedPercent: passed ? 0 : used, resetsAt: passed ? nil : reset))
            }
            u.asOf = f.mtime
            u.note = "마지막 Codex 사용 시점 기록 기준"
            return u
        }
        u.note = "Codex 사용 기록을 찾지 못했습니다"
        return u
    }

    static func parseISO(_ s: String?) -> Date? {
        guard var s = s else { return nil }
        if let dot = s.firstIndex(of: ".") {   // 소수 초 제거
            let tail = s[dot...].drop { $0 == "." || $0.isNumber }
            s = String(s[..<dot]) + tail
        }
        return ISO8601DateFormatter().date(from: s)
    }

    static func claude() -> ServiceUsage {
        var u = ServiceUsage(id: "Claude Code")
        guard let raw = runTool("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let cred = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = cred["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            u.note = "Claude Code 로그인 정보를 읽지 못했습니다"
            return u
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("desktop-pet/0.1", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var body: Data?
        var code = 0
        URLSession.shared.dataTask(with: req) { d, r, _ in
            body = d
            code = (r as? HTTPURLResponse)?.statusCode ?? 0
            sem.signal()
        }.resume()
        sem.wait()
        guard code == 200, let d = body, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            let expired = ((oauth["expiresAt"] as? Double) ?? 0) / 1000 < Date().timeIntervalSince1970
            u.note = expired || code == 401 ? "로그인 토큰이 만료됐습니다. Claude Code를 한 번 실행하면 갱신됩니다"
                                            : "사용량 조회 실패 (HTTP \(code))"
            return u
        }
        for (key, label) in [("five_hour", "5시간"), ("seven_day", "주간"),
                             ("seven_day_opus", "주간 Opus"), ("seven_day_sonnet", "주간 Sonnet")] {
            guard let w = o[key] as? [String: Any], let used = w["utilization"] as? Double else { continue }
            u.windows.append(UsageWindow(id: "claude-\(key)", label: label, usedPercent: used,
                                         resetsAt: parseISO(w["resets_at"] as? String)))
        }
        u.asOf = Date()
        return u
    }
}

// MARK: - 저장소

final class AIUsageStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var usages: [ServiceUsage] = []
    @Published var loadingUsage = false
    private let queue = DispatchQueue(label: "desktoppet.ai-usage", qos: .utility)
    private var lastClaude: ServiceUsage?

    var anyBusy: Bool { sessions.contains { $0.busy == true } }
    /// 서비스별 주간 잔여율 중 가장 낮은 값
    var lowestWeeklyRemaining: Double? {
        usages.flatMap { $0.windows }.filter { $0.label.hasPrefix("주간") }.map { $0.remaining }.min()
    }

    func refreshSessions() {
        queue.async {
            let s = SessionScanner.scan()
            DispatchQueue.main.async { self.sessions = s }
        }
    }

    func refreshUsage() {
        DispatchQueue.main.async { self.loadingUsage = true }
        queue.async {
            var c = UsageFetcher.claude()
            if c.windows.isEmpty, let old = self.lastClaude {   // 실패 시 직전 값 유지
                c.windows = old.windows
                c.asOf = old.asOf
            } else if !c.windows.isEmpty {
                self.lastClaude = c
            }
            let x = UsageFetcher.codex()
            DispatchQueue.main.async {
                self.usages = [c, x]
                self.loadingUsage = false
            }
        }
    }
}
