// 다마고치 메이커 창: 이미지 넣기 → 미리보기 → 앱 만들기
import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class MakerModel: ObservableObject {
    @Published var source: CGImage? { didSet { regenerate() } }
    @Published var sourceName = ""
    @Published var name = "모찌"
    @Published var style = Style.pixel { didSet { regenerate() } }
    @Published var pixelSize = 64 { didSet { regenerate() } }
    @Published var removeBG = true { didSet { regenerate() } }
    @Published var tolerance = 40.0 { didSet { regenerate() } }
    @Published var outline = true { didSet { regenerate() } }
    @Published var facing = "right"
    @Published var messages = "안녕!\n오늘도 화이팅 💪\n잠깐 쉬었다 할까?\n물 한 잔 마셔요"
    @Published var features = Set<String>()
    @Published var result: SpriteGen.Result?
    @Published var error: String?
    @Published var built: URL?
    @Published var busy = false
    private var generation = 0

    var options: MakeOptions {
        MakeOptions(style: style, pixelSize: pixelSize, removeBackground: removeBG,
                    tolerance: tolerance, outline: outline, facing: facing)
    }

    func open(_ url: URL) {
        guard let img = SpriteGen.load(url) else { error = "이미지를 읽지 못했습니다"; return }
        sourceName = url.lastPathComponent
        let base = url.deletingPathExtension().lastPathComponent
        if name == "모찌" || name.isEmpty { name = base }
        built = nil
        source = img
    }

    func chooseFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { open(u) }
    }

    /// 옵션이 바뀔 때마다 다시 그린다 (마지막 요청만 반영)
    func regenerate() {
        guard let src = source else { result = nil; return }
        generation += 1
        let g = generation
        let o = options
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try SpriteGen.make(src, o) }
            DispatchQueue.main.async {
                guard g == self.generation else { return }
                switch r {
                case .success(let v): self.result = v; self.error = nil
                case .failure(let e): self.result = nil; self.error = e.localizedDescription
                }
            }
        }
    }

    func build() {
        guard let r = result else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "여기에 만들기"
        p.message = "다마고치 앱을 저장할 폴더를 고르세요"
        let apps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        p.directoryURL = apps
        guard p.runModal() == .OK, let dir = p.url else { return }
        busy = true
        let msgs = messages.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let n = name, o = options
        let feats = AppBuilder.catalog.map { $0.id }.filter { features.contains($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Result { try AppBuilder.build(name: n, result: r, options: o, messages: msgs, features: feats, into: dir) }
            DispatchQueue.main.async {
                self.busy = false
                switch out {
                case .success(let u): self.built = u; self.error = nil
                case .failure(let e): self.error = e.localizedDescription
                }
            }
        }
    }
}

// MARK: - 애니메이션 미리보기 한 칸

struct AnimTile: View {
    let title: String
    let frames: [CGImage]
    let interval: Double
    let pixel: Bool

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: interval)) { ctx in
                let k = frames.isEmpty ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / interval) % frames.count
                Group {
                    if frames.isEmpty {
                        Color.clear
                    } else {
                        Image(decorative: frames[k], scale: 1)
                            .interpolation(pixel ? .none : .high)
                            .resizable()
                    }
                }
                .frame(width: 128, height: 128)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - 메인 화면

struct MakerView: View {
    @ObservedObject var m: MakerModel
    @State private var dropping = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("1. 캐릭터 이미지") {
                    HStack {
                        Text(m.sourceName.isEmpty ? "PNG·JPG를 오른쪽에 끌어다 놓거나" : m.sourceName)
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button("이미지 고르기…") { m.chooseFile() }
                    }
                    Toggle("배경 자동으로 지우기", isOn: $m.removeBG)
                    if m.removeBG {
                        LabeledContent("지울 범위") {
                            Slider(value: $m.tolerance, in: 5...120)
                        }
                    }
                    Picker("그림이 보는 방향", selection: $m.facing) {
                        Text("오른쪽").tag("right")
                        Text("왼쪽").tag("left")
                        Text("정면").tag("front")
                    }
                }
                Section("2. 스타일") {
                    Picker("모양", selection: $m.style) {
                        ForEach(Style.allCases) { Text($0.label).tag($0) }
                    }
                    if m.style == .pixel {
                        Picker("도트 크기", selection: $m.pixelSize) {
                            Text("32 (굵게)").tag(32)
                            Text("48").tag(48)
                            Text("64 (섬세하게)").tag(64)
                        }
                        Toggle("외곽선 넣기", isOn: $m.outline)
                    }
                }
                Section("3. 이름과 말풍선") {
                    TextField("이름", text: $m.name)
                    VStack(alignment: .leading) {
                        Text("클릭하면 하는 말 (한 줄에 하나)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $m.messages).frame(height: 80).font(.body)
                    }
                }
                Section {
                    ForEach(AppBuilder.catalog, id: \.id) { f in
                        Toggle(isOn: Binding(get: { m.features.contains(f.id) },
                                             set: { if $0 { m.features.insert(f.id) } else { m.features.remove(f.id) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title)
                                Text(f.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("4. 기능 (선택)")
                } footer: {
                    Text("기능을 켜면 클릭했을 때 패널이 열리고, 알릴 일이 생기면 말풍선으로 알려 줍니다. 나만의 기능 추가는 docs/EXTENDING.md 참고.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        m.build()
                    } label: {
                        Text(m.busy ? "만드는 중…" : "다마고치 앱 만들기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(m.result == nil || m.busy || m.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let u = m.built {
                        Text("완성: \(u.lastPathComponent)").font(.callout)
                        HStack {
                            Button("지금 실행") { NSWorkspace.shared.open(u) }
                            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                        }
                    }
                    if let e = m.error {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 380)

            Divider()

            VStack(spacing: 14) {
                if let r = m.result {
                    let px = m.style == .pixel
                    Text("미리보기").font(.headline)
                    HStack(spacing: 12) {
                        AnimTile(title: "기본", frames: r.rows[0], interval: 0.40, pixel: px)
                        AnimTile(title: "걷기", frames: r.rows[1], interval: 0.13, pixel: px)
                    }
                    HStack(spacing: 12) {
                        AnimTile(title: "클릭 반응", frames: r.rows[2], interval: 0.14, pixel: px)
                        AnimTile(title: "잠 (작업 중)", frames: r.rows[3], interval: 0.70, pixel: px)
                    }
                } else {
                    Spacer()
                    Image(systemName: "photo.badge.plus").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("캐릭터 이미지를 여기에 끌어다 놓으세요").font(.title3)
                    Text("배경이 투명한 PNG가 가장 깔끔합니다.\n단색 배경은 자동으로 지워 드려요.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(dropping ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .padding(8))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }
                m.open(u)
                return true
            } isTargeted: { dropping = $0 }
        }
        .frame(width: 900, height: 640)
    }
}
