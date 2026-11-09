// Draws the 1024×1024 app icon: a stack of photos with an arrow into an external drive.
//
//   swift app/icon/render-icon.swift OUTPUT.png
//
// app/build.sh turns the PNG into AppIcon.icns, so the repository only holds this source.
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift render-icon.swift OUTPUT.png\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let canvasSize = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

func fillVerticalGradient(in path: CGPath, top: CGColor, bottom: CGColor) {
    let bounds = path.boundingBox
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1])!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
    context.restoreGState()
}

func roundedRectangle(_ rectangle: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rectangle, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func withShadow(blur: CGFloat, offsetY: CGFloat, opacity: CGFloat, draw: () -> Void) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: offsetY), blur: blur, color: color(0, 0, 0, opacity))
    draw()
    context.restoreGState()
}

// Background: the macOS icon grid's 824-point rounded square, with a blue gradient.
let iconBody = roundedRectangle(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 186)
withShadow(blur: 30, offsetY: -14, opacity: 0.35) {
    context.addPath(iconBody)
    context.setFillColor(color(0.25, 0.42, 0.95))
    context.fillPath()
}
fillVerticalGradient(in: iconBody, top: color(0.36, 0.72, 1.0), bottom: color(0.25, 0.30, 0.86))

// A photo card: white frame, sky, sun and two hills.
func drawPhotoCard(center: CGPoint, rotationDegrees: CGFloat, size: CGSize, isFront: Bool) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotationDegrees * .pi / 180)
    let frame = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

    withShadow(blur: 24, offsetY: -10, opacity: 0.30) {
        context.addPath(roundedRectangle(frame, radius: 28))
        context.setFillColor(color(1, 1, 1, isFront ? 1 : 0.82))
        context.fillPath()
    }

    if isFront {
        let picture = frame.insetBy(dx: 26, dy: 26)
        let picturePath = roundedRectangle(picture, radius: 14)
        fillVerticalGradient(in: picturePath, top: color(0.55, 0.82, 1.0), bottom: color(0.82, 0.93, 1.0))

        context.saveGState()
        context.addPath(picturePath)
        context.clip()

        context.setFillColor(color(1.0, 0.80, 0.25))
        context.fillEllipse(in: CGRect(x: picture.maxX - 120, y: picture.maxY - 120, width: 72, height: 72))

        let farHill = CGMutablePath()
        farHill.move(to: CGPoint(x: picture.minX - 20, y: picture.minY))
        farHill.addLine(to: CGPoint(x: picture.minX + picture.width * 0.30, y: picture.minY + picture.height * 0.66))
        farHill.addLine(to: CGPoint(x: picture.minX + picture.width * 0.62, y: picture.minY))
        farHill.closeSubpath()
        context.addPath(farHill)
        context.setFillColor(color(0.33, 0.68, 0.45))
        context.fillPath()

        let nearHill = CGMutablePath()
        nearHill.move(to: CGPoint(x: picture.minX + picture.width * 0.30, y: picture.minY))
        nearHill.addLine(to: CGPoint(x: picture.minX + picture.width * 0.68, y: picture.minY + picture.height * 0.48))
        nearHill.addLine(to: CGPoint(x: picture.maxX + 30, y: picture.minY))
        nearHill.closeSubpath()
        context.addPath(nearHill)
        context.setFillColor(color(0.20, 0.52, 0.36))
        context.fillPath()

        context.restoreGState()
    }
    context.restoreGState()
}

let cardSize = CGSize(width: 430, height: 330)
drawPhotoCard(center: CGPoint(x: 538, y: 640), rotationDegrees: 9, size: cardSize, isFront: false)
drawPhotoCard(center: CGPoint(x: 494, y: 626), rotationDegrees: -6, size: cardSize, isFront: true)

// The external drive.
let drive = CGRect(x: 236, y: 178, width: 552, height: 136)
let drivePath = roundedRectangle(drive, radius: 38)
withShadow(blur: 22, offsetY: -8, opacity: 0.35) {
    context.addPath(drivePath)
    context.setFillColor(color(0.16, 0.17, 0.22))
    context.fillPath()
}
fillVerticalGradient(in: drivePath, top: color(0.34, 0.36, 0.43), bottom: color(0.13, 0.14, 0.18))
context.setFillColor(color(0.08, 0.09, 0.12))
context.fill(CGRect(x: drive.minX + 56, y: drive.midY - 7, width: 300, height: 14))
context.setFillColor(color(0.30, 0.90, 0.45))
context.fillEllipse(in: CGRect(x: drive.maxX - 92, y: drive.midY - 17, width: 34, height: 34))

// The arrow from the photos into the drive.
let arrowCenterX: CGFloat = 512
let arrow = CGMutablePath()
arrow.addLines(between: [
    CGPoint(x: arrowCenterX - 30, y: 468),
    CGPoint(x: arrowCenterX + 30, y: 468),
    CGPoint(x: arrowCenterX + 30, y: 380),
    CGPoint(x: arrowCenterX + 86, y: 380),
    CGPoint(x: arrowCenterX, y: 300),
    CGPoint(x: arrowCenterX - 86, y: 380),
    CGPoint(x: arrowCenterX - 30, y: 380),
])
arrow.closeSubpath()
withShadow(blur: 12, offsetY: -4, opacity: 0.30) {
    context.addPath(arrow)
    context.setFillColor(color(1, 1, 1))
    context.fillPath()
}

let image = context.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: outputURL)
