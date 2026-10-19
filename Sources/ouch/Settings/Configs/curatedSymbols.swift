import AppKit
import SwiftUI

let curatedSymbols: [String] = [
    "star.fill", "bolt.fill", "flame.fill", "leaf.fill", "heart.fill", "moon.fill", "sun.max.fill", "cloud.fill",
    "drop.fill", "snowflake", "sparkles", "wand.and.stars", "paintbrush.fill", "paintpalette.fill", "bucket.fill",
    "gamecontroller.fill", "keyboard", "command", "option", "control", "laptopcomputer", "desktopcomputer", "display",
    "macwindow", "square.grid.2x2.fill", "rectangle.split.3x1.fill", "sidebar.left", "slider.horizontal.3",
    "gearshape.fill", "wrench.fill", "hammer.fill", "briefcase.fill", "book.fill", "graduationcap.fill", "pencil",
    "terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu.fill", "hare.fill", "tortoise.fill", "airplane",
    "car.fill", "bicycle", "figure.run", "music.note", "headphones", "film.fill", "camera.fill", "photo.fill",
    "theatermasks.fill", "crown.fill", "trophy.fill", "flag.fill", "bell.fill", "bookmark.fill", "tag.fill", "pin.fill",
    "lock.fill", "key.fill", "globe", "map.fill", "cube.fill", "shippingbox.fill", "puzzlepiece.fill",
    "lightbulb.fill", "atom", "pawprint.fill", "tree.fill", "mountain.2.fill", "wind", "rainbow", "party.popper.fill"
].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
