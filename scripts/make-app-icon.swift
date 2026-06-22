import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: make-app-icon.swift input.png output.png\n", stderr)
    exit(2)
}

guard let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("could not load input icon\n", stderr)
    exit(1)
}

let size = NSSize(width: 1024, height: 1024)
let canvas = NSImage(size: size)
canvas.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let mask = NSBezierPath(
    roundedRect: NSRect(origin: .zero, size: size),
    xRadius: 224,
    yRadius: 224
)
mask.addClip()
source.draw(
    in: NSRect(origin: .zero, size: size),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1
)
canvas.unlockFocus()

guard
    let tiff = canvas.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("could not render output icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
