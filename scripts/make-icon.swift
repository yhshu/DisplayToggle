import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let inset: CGFloat = 100, r = NSRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
let shape = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -12); sh.set()
NSColor.white.setFill(); shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()
NSGradient(colors: [NSColor(red: 0.30, green: 0.55, blue: 1.0, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.92, alpha: 1)])!.draw(in: shape, angle: -60)
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium).applying(.init(paletteColors: [.white]))
let sym = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let sz = sym.size
sym.draw(in: NSRect(x: (S - sz.width)/2, y: (S - sz.height)/2 + 10, width: sz.width, height: sz.height))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
