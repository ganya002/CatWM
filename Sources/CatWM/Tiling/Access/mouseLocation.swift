import AppKit
import ApplicationServices

func mouseLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
