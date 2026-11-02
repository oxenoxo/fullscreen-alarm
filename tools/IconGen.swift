import Cocoa

// 生成 iOS 27 风格的多层液态玻璃图标：深色玻璃底 + 白色表盘 + 顶部镜面高光

let size: CGFloat = 1024
let inset: CGFloat = 100          // macOS 图标留边
let side = size - inset * 2
let radius: CGFloat = side * 0.2237

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocusFlipped(false)
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let rect = CGRect(x: inset, y: inset, width: side, height: side)

// 外层柔和投影，让玻璃浮起来
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.black.setFill()
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
ctx.restoreGState()

// 玻璃底：深蓝紫 → 近黑
let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
body.addClip()
if let g = NSGradient(colors: [
    NSColor(srgbRed: 0.995, green: 0.995, blue: 1.0, alpha: 1),
    NSColor(srgbRed: 0.895, green: 0.905, blue: 0.935, alpha: 1),
]) {
    g.draw(in: rect, angle: -62)
}

// 内部折射光斑（Liquid Glass 的"扩散"感）
if let warm = NSGradient(colors: [
    NSColor(srgbRed: 0.78, green: 0.83, blue: 0.92, alpha: 0.55),
    NSColor(srgbRed: 0.78, green: 0.83, blue: 0.92, alpha: 0.0),
]) {
    warm.draw(in: rect, relativeCenterPosition: NSPoint(x: -0.55, y: 0.42))
}
if let cool = NSGradient(colors: [
    NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 0.70),
    NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 0.0),
]) {
    cool.draw(in: rect, relativeCenterPosition: NSPoint(x: 0.60, y: -0.30))
}

// 顶部镜面高光
if let spec = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.85),
    NSColor(white: 1, alpha: 0.18),
    NSColor(white: 1, alpha: 0.0),
]) {
    spec.draw(in: CGRect(x: rect.minX, y: rect.midY,
                         width: side, height: side * 0.5), angle: -90)
}

// 表盘：细圆环
let dialRect = CGRect(x: rect.midX - side * 0.29, y: rect.midY - side * 0.29,
                      width: side * 0.58, height: side * 0.58)
let dial = NSBezierPath(ovalIn: dialRect)
dial.lineWidth = side * 0.017
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.94).setStroke()
dial.stroke()

// 12 个刻度，12 点/3点/6点/9点加粗
for i in 0..<12 {
    let angle = CGFloat(i) / 12.0 * 2 * .pi
    let isMajor = i % 3 == 0
    let outer = side * 0.245
    let inner = side * (isMajor ? 0.213 : 0.226)
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let p1 = CGPoint(x: c.x + cos(angle) * outer, y: c.y + sin(angle) * outer)
    let p2 = CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner)
    let tick = NSBezierPath()
    tick.move(to: p1)
    tick.line(to: p2)
    tick.lineWidth = isMajor ? side * 0.013 : side * 0.007
    tick.lineCapStyle = .round
    NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: isMajor ? 0.90 : 0.42).setStroke()
    tick.stroke()
}

// 指针：时针指向 8 点方向，分针指向 12 点——"还有 20 分钟"的暗示
func hand(angleDeg: CGFloat, length: CGFloat, width: CGFloat, alpha: CGFloat) {
    let a = (90 - angleDeg) * .pi / 180
    let c = CGPoint(x: rect.midX, y: rect.midY)
    let tip = CGPoint(x: c.x + cos(a) * length, y: c.y + sin(a) * length)
    let p = NSBezierPath()
    p.move(to: c)
    p.line(to: tip)
    p.lineWidth = width
    p.lineCapStyle = .round
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: alpha).setStroke()
    p.stroke()
}

hand(angleDeg: 240, length: side * 0.112, width: side * 0.027, alpha: 0.96)  // 时针
hand(angleDeg: 0, length: side * 0.150, width: side * 0.020, alpha: 0.96)    // 分针

// 中心点
let dot = NSBezierPath(ovalIn: CGRect(x: rect.midX - side * 0.017, y: rect.midY - side * 0.017,
                                      width: side * 0.034, height: side * 0.034))
NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.98).setFill()
dot.fill()

ctx.resetClip()

// 内描边：iOS 27 的"加深边缘"
let edge = NSBezierPath(roundedRect: rect.insetBy(dx: side * 0.004, dy: side * 0.004),
                        xRadius: radius, yRadius: radius)
edge.lineWidth = side * 0.008
NSColor(srgbRed: 0.55, green: 0.56, blue: 0.60, alpha: 0.28).setStroke()
edge.stroke()

image.unlockFocus()

// 输出
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: "\(outDir)/icon_1024.png"))
print("icon written to \(outDir)/icon_1024.png")
