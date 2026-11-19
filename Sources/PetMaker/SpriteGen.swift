// 이미지 한 장 → 다마고치 스프라이트 시트 (기본·걷기·기쁨·잠, 4줄)
import AppKit
import CoreGraphics

enum Style: String, CaseIterable, Identifiable {
    case pixel, smooth
    var id: String { rawValue }
    var label: String { self == .pixel ? "도트(픽셀 아트)" : "원본 그대로(부드럽게)" }
}

struct MakeOptions {
    var style: Style = .pixel
    var pixelSize = 64            // 도트 스타일일 때 한 칸 크기 (32·48·64)
    var removeBackground = true
    var tolerance = 40.0          // 배경색과 얼마나 비슷하면 지울지 (0~120)
    var outline = true            // 도트 스타일 외곽선
    var facing = "right"          // 원본 그림이 보는 방향
    var cell: Int { style == .pixel ? pixelSize : 160 }
}

// MARK: - RGBA 비트맵

struct Bitmap {
    let w: Int, h: Int
    var px: [UInt8]   // RGBA, 미리 곱한 알파, 0행 = 맨 위

    static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    init(w: Int, h: Int) {
        self.w = w; self.h = h
        px = [UInt8](repeating: 0, count: w * h * 4)
    }

    init(_ cg: CGImage, maxSide: Int = 1024) {
        let s = min(1.0, Double(maxSide) / Double(max(cg.width, cg.height)))
        w = max(1, Int(Double(cg.width) * s)); h = max(1, Int(Double(cg.height) * s))
        let ctx = Bitmap.context(w, h)
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        px = Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    func cgImage() -> CGImage {
        let ctx = Bitmap.context(w, h)
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        px.withUnsafeBufferPointer { src in p.update(from: src.baseAddress!, count: w * h * 4) }
        return ctx.makeImage()!
    }

    @inline(__always) func i(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
    func alpha(_ x: Int, _ y: Int) -> UInt8 { px[i(x, y) + 3] }
}

// MARK: - 배경 지우기·자르기·도트화

enum SpriteGen {
    /// 네 모서리가 모두 불투명하면 배경이 있다고 보고, 가장자리에서 이어진 비슷한 색을 지운다
    static func removeBackground(_ b: inout Bitmap, tolerance: Double) {
        let corners = [(0, 0), (b.w - 1, 0), (0, b.h - 1), (b.w - 1, b.h - 1)]
        guard corners.allSatisfy({ b.alpha($0.0, $0.1) > 240 }) else { return }   // 이미 투명 배경
        let refs = corners.map { c -> (Double, Double, Double) in
            let k = b.i(c.0, c.1)
            return (Double(b.px[k]), Double(b.px[k + 1]), Double(b.px[k + 2]))
        }
        func near(_ x: Int, _ y: Int) -> Bool {
            let k = b.i(x, y)
            let r = Double(b.px[k]), g = Double(b.px[k + 1]), bl = Double(b.px[k + 2])
            return refs.contains { ((r - $0.0) * (r - $0.0) + (g - $0.1) * (g - $0.1) + (bl - $0.2) * (bl - $0.2)).squareRoot() <= tolerance }
        }
        var seen = [Bool](repeating: false, count: b.w * b.h)
        var stack: [(Int, Int)] = []
        for x in 0..<b.w { stack.append((x, 0)); stack.append((x, b.h - 1)) }
        for y in 0..<b.h { stack.append((0, y)); stack.append((b.w - 1, y)) }
        while let (x, y) = stack.popLast() {
            let n = y * b.w + x
            if seen[n] { continue }
            seen[n] = true
            guard near(x, y) else { continue }
            let k = n * 4
            b.px[k] = 0; b.px[k + 1] = 0; b.px[k + 2] = 0; b.px[k + 3] = 0
            if x > 0 { stack.append((x - 1, y)) }
            if x < b.w - 1 { stack.append((x + 1, y)) }
            if y > 0 { stack.append((x, y - 1)) }
            if y < b.h - 1 { stack.append((x, y + 1)) }
        }
    }

    /// 투명한 여백을 잘라 캐릭터만 남긴다
    static func trim(_ b: Bitmap) -> CGImage? {
        var minX = b.w, minY = b.h, maxX = -1, maxY = -1
        for y in 0..<b.h { for x in 0..<b.w where b.alpha(x, y) > 16 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        return b.cgImage().cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// 칸 안에 들어갈 캐릭터 크기 (가로 84%, 세로 78%)
    static func fit(_ img: CGImage, cell: Int, inset: Int = 0) -> (Int, Int) {
        let bw = Double(cell) * 0.84 - Double(inset * 2), bh = Double(cell) * 0.78 - Double(inset * 2)
        let s = min(bw / Double(img.width), bh / Double(img.height))
        return (max(1, Int((Double(img.width) * s).rounded())), max(1, Int((Double(img.height) * s).rounded())))
    }

    /// 작게 줄인 뒤 알파를 딱 잘라 도트처럼, 원하면 1px 외곽선
    static func pixelize(_ img: CGImage, w: Int, h: Int, outline: Bool) -> CGImage {
        let pad = outline ? 1 : 0
        let ctx = Bitmap.context(w + pad * 2, h + pad * 2)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: pad, y: pad, width: w, height: h))
        var b = Bitmap(w: w + pad * 2, h: h + pad * 2)
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        b.px = Array(UnsafeBufferPointer(start: p, count: b.w * b.h * 4))
        for n in 0..<(b.w * b.h) {
            let k = n * 4
            let a = Int(b.px[k + 3])
            if a < 110 {
                b.px[k] = 0; b.px[k + 1] = 0; b.px[k + 2] = 0; b.px[k + 3] = 0
            } else if a < 255 {   // 미리 곱한 알파 풀기
                for c in 0..<3 { b.px[k + c] = UInt8(min(255, Int(b.px[k + c]) * 255 / a)) }
                b.px[k + 3] = 255
            }
        }
        if outline {
            let src = b
            for y in 0..<b.h { for x in 0..<b.w where src.alpha(x, y) == 0 {
                var near: Int?
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < b.w, ny < b.h, src.alpha(nx, ny) > 0 { near = src.i(nx, ny); break }
                }
                if let s = near {   // 이웃 색을 아주 어둡게
                    let k = b.i(x, y)
                    for c in 0..<3 { b.px[k + c] = UInt8(Double(src.px[s + c]) * 0.28) }
                    b.px[k + 3] = 255
                }
            } }
        }
        return b.cgImage()
    }

    // MARK: 효과 그림 (64칸 기준 좌표, 위에서부터)

    static let heart = ["01010", "11111", "11111", "01110", "00100"]
    static let zBig = ["11111", "00010", "00100", "01000", "11111"]
    static let zSmall = ["111", "010", "111"]
    static let spark = ["00100", "00100", "11011", "00100", "00100"]

    static func stamp(_ ctx: CGContext, _ pat: [String], _ ox: Int, _ oy: Int, _ hex: UInt32, cell: Int) {
        let k = CGFloat(cell) / 64           // 위치는 칸 크기에 비례
        let u = max(1, k.rounded(.down))     // 효과 도트 한 칸은 최소 1px
        ctx.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                                 blue: CGFloat(hex & 0xff) / 255, alpha: 1))
        for (j, row) in pat.enumerated() {
            for (i, ch) in row.enumerated() where ch == "1" {
                let x = CGFloat(ox) * k + CGFloat(i) * u, y = CGFloat(cell) - CGFloat(oy) * k - CGFloat(j + 1) * u
                ctx.fill(CGRect(x: x.rounded(), y: y.rounded(), width: ceil(u), height: ceil(u)))
            }
        }
    }

    // MARK: 프레임

    struct Pose {
        var sx = 1.0, sy = 1.0, dy = 0.0, dx = 0.0, rot = 0.0
        var tint = 0.0
        var fx: [(String, Int, Int)] = []
    }

    static let poses: [[Pose]] = [
        // 기본: 숨쉬기
        [Pose(), Pose(sx: 1.02, sy: 0.97), Pose(), Pose(sx: 1.03, sy: 0.95)],
        // 걷기: 통통 + 살짝 기울기
        [Pose(rot: -3), Pose(sx: 0.99, sy: 1.02, dy: 2, dx: 1), Pose(rot: 3), Pose(sx: 0.99, sy: 1.02, dy: 2, dx: -1)],
        // 기쁨: 점프 + 하트
        [Pose(sx: 1.05, sy: 0.93),
         Pose(sx: 0.97, sy: 1.04, dy: 6, fx: [("heart", 2, 14), ("heart", 57, 20)]),
         Pose(sx: 0.98, sy: 1.03, dy: 9, fx: [("heart", 1, 8), ("heart", 58, 13), ("spark", 50, 2)]),
         Pose(dy: 3, fx: [("heart", 2, 3), ("heart", 57, 8)])],
        // 잠: 납작 + 살짝 어둡게 + Zzz
        [Pose(sx: 1.06, sy: 0.86, tint: 0.16, fx: [("z", 54, 14)]),
         Pose(sx: 1.07, sy: 0.84, tint: 0.16, fx: [("z", 55, 11), ("Z", 57, 2)])],
    ]

    static func frame(_ base: CGImage, w: Int, h: Int, pose p: Pose, cell: Int, pixel: Bool) -> CGImage {
        let ctx = Bitmap.context(cell, cell)
        ctx.interpolationQuality = pixel ? .none : .high
        let u = CGFloat(cell) / 64
        var fw = CGFloat(w) * p.sx, fh = CGFloat(h) * p.sy
        if pixel { fw = fw.rounded(); fh = fh.rounded() }
        ctx.saveGState()
        ctx.translateBy(x: (CGFloat(cell) / 2 + CGFloat(p.dx) * u).rounded(), y: (2 * u + CGFloat(p.dy) * u).rounded())
        if !pixel && p.rot != 0 { ctx.rotate(by: CGFloat(p.rot) * .pi / 180) }
        ctx.draw(base, in: CGRect(x: (-fw / 2).rounded(), y: 0, width: fw, height: fh))
        if p.tint > 0 {
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(CGColor(gray: 0, alpha: p.tint))
            ctx.fill(CGRect(x: -fw, y: 0, width: fw * 2, height: fh))
            ctx.setBlendMode(.normal)
        }
        ctx.restoreGState()
        for (k, x, y) in p.fx {
            switch k {
            case "heart": stamp(ctx, heart, x, y, 0xFF6B8B, cell: cell)
            case "spark": stamp(ctx, spark, x, y, 0xFFC94D, cell: cell)
            case "z": stamp(ctx, zSmall, x, y, 0x8E9AD0, cell: cell)
            default: stamp(ctx, zBig, x, y, 0x8E9AD0, cell: cell)
            }
        }
        return ctx.makeImage()!
    }

    struct Result {
        let rows: [[CGImage]]     // 기본·걷기·기쁨·잠
        let sheetPNG: Data
        let cell: Int
        let character: CGImage    // 아이콘용 (배경 지운 원본)
    }

    enum Failure: LocalizedError {
        case unreadable, empty
        var errorDescription: String? {
            self == .unreadable ? "이미지를 읽지 못했습니다" : "캐릭터를 찾지 못했습니다 (배경 지우기 허용 범위를 낮춰 보세요)"
        }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func make(_ source: CGImage, _ o: MakeOptions) throws -> Result {
        var b = Bitmap(source)
        if o.removeBackground { removeBackground(&b, tolerance: o.tolerance) }
        guard let char = trim(b) else { throw Failure.empty }
        let cell = o.cell
        let pixel = o.style == .pixel
        var base = char
        var (w, h) = fit(char, cell: cell)
        if pixel {
            let (iw, ih) = fit(char, cell: cell, inset: o.outline ? 1 : 0)
            base = pixelize(char, w: iw, h: ih, outline: o.outline)
            w = base.width; h = base.height
        }
        let rows = poses.map { row in row.map { frame(base, w: w, h: h, pose: $0, cell: cell, pixel: pixel) } }
        // 시트: 4칸 × 4줄, 0줄이 맨 위
        let sheet = Bitmap.context(cell * 4, cell * 4)
        for (r, row) in rows.enumerated() {
            for (c, f) in row.enumerated() {
                sheet.draw(f, in: CGRect(x: c * cell, y: (3 - r) * cell, width: cell, height: cell))
            }
        }
        let rep = NSBitmapImageRep(cgImage: sheet.makeImage()!)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.unreadable }
        return Result(rows: rows, sheetPNG: png, cell: cell, character: char)
    }
}
