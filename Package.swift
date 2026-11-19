// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopPetMaker",
    platforms: [.macOS(.v13)],
    targets: [
        // 만들어진 다마고치 앱 안에 들어가는 실행 파일 (sheet.png + pet.json 을 읽어 화면에 띄움)
        .executableTarget(name: "PetRuntime", path: "Sources/PetRuntime"),
        // 이미지 → 다마고치 앱을 만드는 프로그램 (창 + 명령줄)
        .executableTarget(name: "PetMaker", path: "Sources/PetMaker"),
    ]
)
