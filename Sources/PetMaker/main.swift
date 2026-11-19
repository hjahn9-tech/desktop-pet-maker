// 다마고치 메이커: 창으로 쓰거나, --cli 로 명령줄에서 쓴다.
//
//   PetMaker --cli <이미지> [--name 이름] [--style pixel|smooth] [--size 32|48|64]
//            [--facing right|left|front] [--keep-bg] [--tolerance 40] [--no-outline]
//            [--say "문구1|문구2"] [--out 폴더] [--sheet 시트.png]
import AppKit
import SwiftUI

func runCLI(_ args: [String]) -> Int32 {
    func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    let valueFlags: Set<String> = ["--name", "--style", "--size", "--facing", "--tolerance", "--say", "--out", "--sheet", "--features"]
    var input: String?
    var k = 0
    while k < args.count {
        if valueFlags.contains(args[k]) { k += 2; continue }
        if !args[k].hasPrefix("--") && input == nil { input = args[k] }
        k += 1
    }
    guard let input = input else {
        print("사용법: PetMaker --cli <이미지> [--name 이름] [--style pixel|smooth] [--size 64] [--out 폴더]")
        return 2
    }
    let url = URL(fileURLWithPath: input)
    guard let img = SpriteGen.load(url) else { print("이미지를 읽지 못했습니다: \(input)"); return 1 }
    var o = MakeOptions()
    o.style = value("--style") == "smooth" ? .smooth : .pixel
    o.pixelSize = Int(value("--size") ?? "") ?? 64
    o.facing = value("--facing") ?? "right"
    o.removeBackground = !args.contains("--keep-bg")
    o.tolerance = Double(value("--tolerance") ?? "") ?? 40
    o.outline = !args.contains("--no-outline")
    let name = value("--name") ?? url.deletingPathExtension().lastPathComponent
    let msgs = (value("--say") ?? "안녕!|오늘도 화이팅|잠깐 쉬었다 할까?").split(separator: "|").map(String.init)
    do {
        let r = try SpriteGen.make(img, o)
        if let sheet = value("--sheet") {
            try r.sheetPNG.write(to: URL(fileURLWithPath: sheet))
            print("시트: \(sheet)")
        }
        let out = URL(fileURLWithPath: value("--out") ?? FileManager.default.currentDirectoryPath)
        if value("--sheet") == nil || args.contains("--out") {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let feats = (value("--features") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let app = try AppBuilder.build(name: name, result: r, options: o, messages: msgs, features: feats, into: out)
            print("완성: \(app.path)")
        }
        return 0
    } catch {
        print("실패: \(error.localizedDescription)")
        return 1
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--cli") {
    exit(runCLI(args.filter { $0 != "--cli" }))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = MakerModel()

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "다마고치 메이커"
        window.contentViewController = NSHostingController(rootView: MakerView(m: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 처음 열면 예시 캐릭터를 보여 준다
        if let ex = Bundle.main.url(forResource: "mochi", withExtension: "png") { model.open(ex); model.name = "모찌" }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func application(_ s: NSApplication, open urls: [URL]) {
        if let u = urls.first { model.open(u) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
