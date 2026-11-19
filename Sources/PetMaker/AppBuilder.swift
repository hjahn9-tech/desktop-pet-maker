// 스프라이트 시트 + 설정 → 「이름.app」 다마고치 앱 번들
import AppKit

enum AppBuilder {
    enum Failure: LocalizedError {
        case noRuntime
        var errorDescription: String? { "PetRuntime 실행 파일을 찾지 못했습니다. build.sh 로 만든 PetMaker.app 에서 실행해 주세요." }
    }

    /// 만들어진 앱에 넣을 실행 파일: PetMaker.app 안의 Resources/PetRuntime, 없으면 같은 폴더의 PetRuntime
    static var runtimeURL: URL? {
        if let u = Bundle.main.url(forResource: "PetRuntime", withExtension: nil) { return u }
        let side = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("PetRuntime")
        return FileManager.default.isExecutableFile(atPath: side.path) ? side : nil
    }

    /// 번들 ID에 쓸 영문 이름 (한글 이름이면 유니코드 값으로)
    static func slug(_ name: String) -> String {
        let ascii = name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        let s = String(String.UnicodeScalarView(ascii))
        if !s.isEmpty { return s }
        return "pet" + name.unicodeScalars.prefix(6).map { String($0.value, radix: 16) }.joined()
    }

    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    /// 캐릭터 그림으로 앱 아이콘(.icns) 만들기
    static func writeIcon(_ character: CGImage, pixel: Bool, to icns: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("petmaker-\(UUID().uuidString).iconset")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for s in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = s * scale
                let ctx = Bitmap.context(px, px)
                ctx.interpolationQuality = pixel ? .none : .high
                let m = Double(px) * 0.9
                let k = min(m / Double(character.width), m / Double(character.height))
                let w = Double(character.width) * k, h = Double(character.height) * k
                ctx.draw(character, in: CGRect(x: (Double(px) - w) / 2, y: (Double(px) - h) / 2, width: w, height: h))
                let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
                let name = scale == 1 ? "icon_\(s)x\(s).png" : "icon_\(s)x\(s)@2x.png"
                try? rep.representation(using: .png, properties: [:])?.write(to: tmp.appendingPathComponent(name))
            }
        }
        run("/usr/bin/iconutil", ["-c", "icns", tmp.path, "-o", icns.path])
    }

    /// 메이커에서 고를 수 있는 기능 (id 는 PetRuntime/Features 의 featureRegistry 와 같아야 함)
    static let catalog: [(id: String, title: String, note: String)] = [
        ("calendar", "오늘 일정", "macOS 캘린더 앱에 연결된 계정(구글 포함)의 오늘 일정, 10분 전 알림"),
        ("gmail", "지메일", "안 읽은 메일과 새 메일 알림 — tools/google_login.py 로 한 번 로그인 필요"),
        ("ai-usage", "AI 사용량", "Claude Code·Codex 실행 중 세션과 주간 사용량, 얼마 안 남으면 알림"),
    ]

    @discardableResult
    static func build(name: String, result r: SpriteGen.Result, options o: MakeOptions,
                      messages: [String], features: [String] = [], into dir: URL) throws -> URL {
        guard let runtime = runtimeURL else { throw Failure.noRuntime }
        let fm = FileManager.default
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let app = dir.appendingPathComponent((safe.isEmpty ? "다마고치" : safe) + ".app")
        if fm.fileExists(atPath: app.path) {
            // 실행 중이면 먼저 끈다
            let id = "local.desktoppet." + slug(name)
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
            try fm.removeItem(at: app)
        }
        let macos = app.appendingPathComponent("Contents/MacOS")
        let res = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.createDirectory(at: res, withIntermediateDirectories: true)
        try fm.copyItem(at: runtime, to: macos.appendingPathComponent("PetRuntime"))
        try r.sheetPNG.write(to: res.appendingPathComponent("sheet.png"))

        let pixel = o.style == .pixel
        let cfg: [String: Any] = [
            "name": safe.isEmpty ? "다마고치" : safe,
            "cell": r.cell,
            "smooth": !pixel,
            "facing": o.facing,
            "displaySize": 100.0,
            "messages": messages,
            "features": features,
        ]
        try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys])
            .write(to: res.appendingPathComponent("pet.json"))
        writeIcon(r.character, pixel: pixel, to: res.appendingPathComponent("AppIcon.icns"))

        let info: [String: Any] = [
            "CFBundleName": safe,
            "CFBundleDisplayName": safe,
            "CFBundleIdentifier": "local.desktoppet." + slug(name),
            "CFBundleExecutable": "PetRuntime",
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "NSCalendarsFullAccessUsageDescription": "오늘 일정을 보여 주려면 캘린더를 읽어야 합니다.",
            "NSCalendarsUsageDescription": "오늘 일정을 보여 주려면 캘린더를 읽어야 합니다.",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
        return app
    }
}
