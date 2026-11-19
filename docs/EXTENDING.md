# 나만의 기능 넣기 가이드

다마고치에 "클릭하면 열리는 패널"과 "알릴 일이 생기면 말풍선"을 붙이는 방법입니다.
메일, 캘린더, AI 토큰 사용량처럼 **내가 자주 확인하는 정보**를 다마고치가 대신 챙겨 보게 만들 수 있습니다.

- 들어 있는 예시 기능 3개: [오늘 일정](#1-오늘-일정-calendar) · [지메일](#2-지메일-gmail) · [AI 사용량](#3-ai-사용량-ai-usage)
- 직접 만들기: [따라 하기 — 「할 일 메모」 기능](#따라-하기--할-일-메모-기능-만들기)
- 아이디어: [이런 기능도 만들 수 있어요](#이런-기능도-만들-수-있어요)
- Claude Code에 맡기기: [Claude Code로 기능 추가하기](#claude-code로-기능-추가하기)

---

## 구조 한눈에 보기

```
다마고치 메이커 (PetMaker)
   │  이미지 → sheet.png
   │  체크한 기능 → pet.json 의 "features": ["calendar", "gmail"]
   ▼
몽이.app
   ├─ MacOS/PetRuntime        ← 모든 다마고치가 같이 쓰는 엔진 (기능 코드가 여기 들어 있음)
   └─ Resources/
        ├─ sheet.png
        └─ pet.json           ← 어떤 기능을 켤지 적혀 있음
```

1. 기능 코드는 전부 `Sources/PetRuntime/Features/` 에 있습니다.
2. 엔진은 `pet.json` 의 `features` 이름을 보고 `featureRegistry` 에서 해당 기능을 만듭니다.
3. 기능을 하나라도 켜면 다마고치를 **클릭할 때 패널**이 열리고(여러 개면 탭), 15초마다 각 기능에게 "알릴 거 있어?"라고 물어 **말풍선**을 띄웁니다.

## 기능 하나 = 함수 네 개

`Sources/PetRuntime/Features/Feature.swift` 의 `PetFeature` 를 따르면 됩니다.

```swift
protocol PetFeature: AnyObject {
    static var id: String { get }              // pet.json 에 적는 이름 (예: "todo")
    var title: String { get }                  // 패널 탭 이름 (예: "할 일")
    var refreshInterval: TimeInterval { get }  // 몇 초마다 새로 고칠지
    func refresh()                             // 데이터 가져오기 (패널 열 때 + 주기마다)
    func takeAttention() -> String?            // 말풍선으로 알릴 말 (없으면 nil)
    func makePanel() -> AnyView                // 클릭하면 보일 화면 (SwiftUI)
}
```

| 하는 일 | 언제 불리나 | 지킬 것 |
|---|---|---|
| `refresh()` | 시작할 때, 패널 열 때, `refreshInterval` 마다 | 메인 스레드에서 불림. 네트워크·파일 읽기는 `DispatchQueue.global().async` 로 돌리고, 결과만 메인에서 반영 |
| `takeAttention()` | 15초마다 | **새로 알릴 게 있을 때 한 번만** 문자열을 돌려주고, 그다음엔 `nil`. 안 그러면 15초마다 같은 말을 함 |
| `makePanel()` | 패널을 처음 만들 때 | `@ObservedObject` 모델을 넘기면 데이터가 바뀔 때 화면도 자동으로 바뀜 |

---

## 따라 하기 — 「할 일 메모」 기능 만들기

`~/Documents/할일.txt` 에 적어 둔 할 일을 패널에 보여 주고, 파일 맨 위에 `!` 로 시작하는 줄이 있으면 말풍선으로 알려 주는 기능입니다. 키나 로그인이 필요 없어 연습용으로 좋습니다.

### 1) 기능 파일 만들기

`Sources/PetRuntime/Features/TodoFeature.swift`:

```swift
import SwiftUI

final class TodoModel: ObservableObject {
    @Published var lines: [String] = []
    let path = NSHomeDirectory() + "/Documents/할일.txt"

    func refresh() {
        DispatchQueue.global().async {
            let text = (try? String(contentsOfFile: self.path, encoding: .utf8)) ?? ""
            let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            DispatchQueue.main.async { self.lines = lines }
        }
    }
}

final class TodoFeature: PetFeature {
    static let id = "todo"
    let title = "할 일"
    let refreshInterval: TimeInterval = 60
    let model = TodoModel()
    private var lastTold: String?

    init() { refresh() }
    func refresh() { model.refresh() }

    // 맨 위 줄이 "!" 로 시작하면, 그 줄이 바뀌었을 때 한 번만 알려 준다
    func takeAttention() -> String? {
        guard let top = model.lines.first, top.hasPrefix("!"), top != lastTold else { return nil }
        lastTold = top
        return "잊지 마세요: " + top.dropFirst()
    }

    func makePanel() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("할 일").font(.headline)
                TodoList(model: model)
            }
            .padding(14)
        )
    }
}

struct TodoList: View {
    @ObservedObject var model: TodoModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.lines.isEmpty { Text("~/Documents/할일.txt 가 비어 있어요").foregroundStyle(.secondary) }
                ForEach(model.lines, id: \.self) { Text("• " + $0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

### 2) 엔진에 등록하기

`Sources/PetRuntime/Features/Feature.swift` 의 `featureRegistry` 에 한 줄:

```swift
let featureRegistry: [String: () -> PetFeature] = [
    CalendarFeature.id: { CalendarFeature() },
    AIUsageFeature.id: { AIUsageFeature() },
    GmailFeature.id: { GmailFeature() },
    TodoFeature.id: { TodoFeature() },        // ← 추가
]
```

### 3) 메이커 체크박스에 보이게 하기

`Sources/PetMaker/AppBuilder.swift` 의 `catalog` 에 한 줄:

```swift
("todo", "할 일 메모", "~/Documents/할일.txt 를 보여 주고 ! 로 시작하는 줄은 알려 줌"),
```

### 4) 다시 빌드하고 다마고치 만들기

```bash
./build.sh
open "build/다마고치 메이커.app"      # 「4. 기능」에서 할 일 메모 체크 → 앱 만들기
# 또는
"build/다마고치 메이커.app/Contents/MacOS/PetMaker" --cli examples/mochi.png --name 모찌 --features todo,calendar
```

> 이미 만든 다마고치 앱은 예전 엔진을 품고 있습니다. 새 기능을 쓰려면 메이커로 **다시 만들어** 주세요.
> (같은 이름으로 만들면 덮어씁니다. 설정한 크기·속도는 그대로 남습니다.)

---

## 들어 있는 예시 기능

### 1. 오늘 일정 (`calendar`)

- macOS **캘린더 앱에 연결된 모든 계정**의 오늘 일정을 보여 줍니다. 구글·iCloud·회사(Exchange) 모두 됩니다.
- 시작 10분 전에 말풍선으로 알려 줍니다.
- **준비**: 구글 캘린더라면 「시스템 설정 › 인터넷 계정 › Google」에서 로그인하고 **캘린더**를 켭니다. 처음 실행할 때 캘린더 접근을 허용합니다.
- 키·토큰이 필요 없어 가장 쉽습니다. 공유받은 캘린더도 캘린더 앱에 보이면 여기에도 보입니다.

### 2. 지메일 (`gmail`)

- 받은편지함의 안 읽은 메일(최대 15통)을 보여 주고, 누르면 지메일에서 엽니다. 새 메일이 오면 "새 메일: 보낸 사람"으로 알려 줍니다.
- 읽기 전용(`gmail.readonly`)이라 메일을 보내거나 지우거나 읽음 처리하지 않습니다.
- **준비 (한 번만, 10분 정도)**
  1. [Google Cloud 콘솔](https://console.cloud.google.com/)에서 새 프로젝트를 만듭니다.
  2. 「API 및 서비스 › 라이브러리」에서 **Gmail API** 를 사용 설정합니다.
  3. 「OAuth 동의 화면」을 만듭니다. 사용자 유형은 외부(회사 Workspace면 내부도 가능), **테스트 사용자에 내 지메일 주소**를 넣습니다.
  4. 「사용자 인증 정보 › 사용자 인증 정보 만들기 › OAuth 클라이언트 ID › **데스크톱 앱**」을 만들고 JSON 을 내려받습니다.
  5. 터미널에서:
     ```bash
     pip3 install google-auth-oauthlib
     python3 tools/google_login.py ~/Downloads/client_secret_XXXX.json
     ```
     브라우저가 열리면 로그인 → 허용. `~/.config/desktop-pet/google_token.json` 이 생기면 끝입니다.
- 테스트 상태의 OAuth 앱은 구글 정책상 로그인이 **7일 뒤 만료**될 수 있습니다. 그러면 패널에 안내가 뜨고, 5번만 다시 하면 됩니다.

### 3. AI 사용량 (`ai-usage`)

- **실행 중인 세션**: Claude Code(`~/.claude/sessions`), Codex CLI(실행 중 프로세스·`~/.codex/sessions`), 그 밖의 에이전트 CLI(gemini·aider·opencode·cursor-agent) 프로세스.
- **사용량**
  - Claude Code: 이 맥의 Claude Code 로그인 정보(키체인)로 5시간·주간 남은 비율을 조회합니다. **공식 공개 API가 아니라** Claude Code 업데이트로 바뀌거나 막힐 수 있습니다.
  - Codex: 마지막으로 Codex를 쓴 시점의 로컬 기록에서 읽습니다(실시간 아님).
- 주간 잔여량이 15% 아래로 내려가면 한 번 알려 줍니다.
- 로그인 정보는 이 맥 안에서만 쓰이고, Anthropic 서버로 사용량을 물을 때만 전송됩니다.

---

## 이런 기능도 만들 수 있어요

| 기능 | 가져올 곳 | 인증 | 말풍선 예시 |
|---|---|---|---|
| 날씨·우산 알림 | [Open-Meteo](https://open-meteo.com/) | 필요 없음 | "오후에 비 와요, 우산!" |
| 뽀모도로 타이머 | 앱 안 타이머 | 필요 없음 | "25분 지났어요, 5분 쉬어요" |
| 물 마시기·스트레칭 | 앱 안 타이머 | 필요 없음 | "물 한 잔!" |
| 깃허브 리뷰 요청·CI 결과 | GitHub API (`gh auth token`) | 개인 토큰 | "PR 리뷰 요청 2건" |
| 슬랙 멘션 | Slack Web API | 봇/사용자 토큰 | "@멘션 3개" |
| 노션 할 일 | Notion API | 통합 토큰 | "오늘 마감 1건" |
| 환율·주가 | 공개 시세 API | 대부분 필요 없음 | "환율 1,400원 넘었어요" |
| 배터리·디스크 | macOS (`IOPowerSources`, `FileManager`) | 필요 없음 | "배터리 15%예요" |
| 빌드·배포 상태 | Vercel·Netlify API | 토큰 | "배포 실패!" |
| 구글 캘린더 (API로 직접) | Google Calendar API | OAuth (`calendar.readonly`) | 캘린더 앱에 없는 공유 캘린더까지 |

### 만들 때 지키면 좋은 것

- **토큰·비밀 값**은 코드에 쓰지 말고 `~/.config/desktop-pet/` 아래 파일(권한 600)이나 키체인에 두세요. 저장소에 올리지 않도록 주의합니다.
- **알림은 한 번만**: `takeAttention()` 에서 이미 알린 항목(ID)을 기억해 두세요.
- **느린 작업은 백그라운드**에서: `refresh()` 는 메인 스레드에서 불리므로 네트워크 요청이 화면을 멈추지 않게 합니다.
- **요청 간격**: 외부 API는 `refreshInterval` 을 60초 이상으로 두는 게 좋습니다.
- **실패해도 조용히**: 네트워크가 끊겨도 앱이 꺼지지 않게, 패널에 짧은 안내만 띄웁니다.

---

## Claude Code로 기능 추가하기

이 저장소를 [Claude Code](https://claude.com/claude-code)로 열고 이렇게 말하면 됩니다.

```
docs/EXTENDING.md 를 읽고, 「깃허브 리뷰 요청」 기능을 만들어 줘.
- gh auth token 으로 토큰을 가져와서
- 나에게 리뷰 요청된 PR 목록을 패널에 보여 주고
- 새 요청이 오면 말풍선으로 알려 줘
- featureRegistry 와 메이커 catalog 에도 등록하고 ./build.sh 로 빌드까지 확인해 줘
```

이 가이드의 구조(함수 네 개, 등록 두 곳, 다시 빌드)를 그대로 따르기 때문에, 원하는 정보와 알림 조건만 말해 주면 됩니다.
