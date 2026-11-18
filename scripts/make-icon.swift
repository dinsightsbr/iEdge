#!/usr/bin/env swift
// Draws the iEdge app icon with CoreGraphics and packs it into Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift [output.icns] [--png <preview.png>]
//
// macOS 26 style: a continuous-corner square on the standard icon grid (824 of 1024 pt, so the
// system shadow has room), a soft gradient, and the sidebar itself: a vertical glass capsule
// resting against the right edge with three tiles, the middle one magnified like the Dock.

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

/// Continuous ("squircle") rounded rectangle: a superellipse blended into straight sides, the
/// shape of the macOS app icon mask.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let r = min(radius, rect.width / 2, rect.height / 2)
    // Corner extent is ~1.28 r for the continuous curve (Apple's corner smoothing ≈ 0.6).
    let e = min(r * 1.28, rect.width / 2, rect.height / 2)
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    path.move(to: CGPoint(x: minX + e, y: maxY))
    path.addLine(to: CGPoint(x: maxX - e, y: maxY))
    path.addCurve(to: CGPoint(x: maxX, y: maxY - e), control1: CGPoint(x: maxX - e * 0.25, y: maxY), control2: CGPoint(x: maxX, y: maxY - e * 0.25))
    path.addLine(to: CGPoint(x: maxX, y: minY + e))
    path.addCurve(to: CGPoint(x: maxX - e, y: minY), control1: CGPoint(x: maxX, y: minY + e * 0.25), control2: CGPoint(x: maxX - e * 0.25, y: minY))
    path.addLine(to: CGPoint(x: minX + e, y: minY))
    path.addCurve(to: CGPoint(x: minX, y: minY + e), control1: CGPoint(x: minX + e * 0.25, y: minY), control2: CGPoint(x: minX, y: minY + e * 0.25))
    path.addLine(to: CGPoint(x: minX, y: maxY - e))
    path.addCurve(to: CGPoint(x: minX + e, y: maxY), control1: CGPoint(x: minX, y: maxY - e * 0.25), control2: CGPoint(x: minX + e * 0.25, y: maxY))
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Draws the icon in a 1024 × 1024 coordinate space (origin bottom-left).
func drawIcon(_ ctx: CGContext) {
    let shape = continuousRect(body, radius: 160)

    // Background: soft sky-to-indigo gradient, lighter at the top like a lit surface.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    linearGradient(ctx, [color(0x7FD3FF), color(0x4F8BFF), color(0x5B4FE0)], from: CGPoint(x: 300, y: body.maxY), to: CGPoint(x: 700, y: body.minY))
    // A faint glow in the upper left, so the flat gradient reads as depth.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 520, options: [])
    ctx.restoreGState()

    // Glass capsule against the right edge of the square.
    let capsuleWidth: CGFloat = 196
    let capsule = CGRect(x: body.maxX - 40 - capsuleWidth, y: 232, width: capsuleWidth, height: 560)
    let capsulePath = CGPath(roundedRect: capsule, cornerWidth: capsuleWidth / 2, cornerHeight: capsuleWidth / 2, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x1B1460, 0.35))
    ctx.addPath(capsulePath)
    ctx.setFillColor(color(0xFFFFFF, 0.30))
    ctx.fillPath()
    ctx.restoreGState()

    // Glass sheen: brighter at the top, and a thin light rim.
    ctx.saveGState()
    ctx.addPath(capsulePath)
    ctx.clip()
    linearGradient(ctx, [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0.08)], from: CGPoint(x: capsule.midX, y: capsule.maxY), to: CGPoint(x: capsule.midX, y: capsule.minY))
    ctx.restoreGState()
    ctx.addPath(capsulePath)
    ctx.setStrokeColor(color(0xFFFFFF, 0.65))
    ctx.setLineWidth(5)
    ctx.strokePath()

    // Tiles: small, magnified (grows into the screen, anchored on the edge side), small.
    let small: CGFloat = 112
    let big: CGFloat = 196
    let anchorX = capsule.maxX - (capsuleWidth - small) / 2   // right side of a resting tile
    let tiles: [(center: CGFloat, size: CGFloat, highlighted: Bool)] = [
        (capsule.maxY - 112, small, false),
        (capsule.midY, big, true),
        (capsule.minY + 112, small, false),
    ]
    for tile in tiles {
        let rect = CGRect(x: anchorX - tile.size, y: tile.center - tile.size / 2, width: tile.size, height: tile.size)
        let circle = CGPath(ellipseIn: rect, transform: nil)
        ctx.saveGState()
        if tile.highlighted {
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x1B1460, 0.40))
            ctx.addPath(circle)
            ctx.setFillColor(color(0xFFFFFF))
            ctx.fillPath()
            ctx.restoreGState()
            // Magnifier glyph: lens and handle in the accent blue.
            let lensRadius = tile.size * 0.2
            let lensCenter = CGPoint(x: rect.midX - tile.size * 0.04, y: rect.midY + tile.size * 0.04)
            ctx.setStrokeColor(color(0x3D6BF0))
            ctx.setLineWidth(tile.size * 0.085)
            ctx.setLineCap(.round)
            ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
            ctx.strokePath()
            let offset = lensRadius * 0.72
            ctx.move(to: CGPoint(x: lensCenter.x + offset, y: lensCenter.y - offset))
            ctx.addLine(to: CGPoint(x: lensCenter.x + lensRadius * 1.75, y: lensCenter.y - lensRadius * 1.75))
            ctx.strokePath()
        } else {
            ctx.addPath(circle)
            ctx.setFillColor(color(0xFFFFFF, 0.55))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
}

func renderPNG(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: Main

var args = Array(CommandLine.arguments.dropFirst())
var previewPath: String?
if let index = args.firstIndex(of: "--png"), index + 1 < args.count {
    previewPath = args[index + 1]
    args.removeSubrange(index...index + 1)
}
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let output = args.first.map { URL(fileURLWithPath: $0) }
    ?? scriptDir.appendingPathComponent("../Resources/AppIcon.icns").standardizedFileURL

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try renderPNG(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
if let previewPath {
    try renderPNG(pixels: 512).write(to: URL(fileURLWithPath: previewPath))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil falhou (\(iconutil.terminationStatus))\n".data(using: .utf8)!)
    exit(1)
}
print("✔ \(output.path)")
