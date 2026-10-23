import AppKit
import SuperShotCore

/// Pure navigation and shortcut resolver for SuperShot history popover interaction.
public struct ShortcutNavigator {
    public static func shortcutIndex(for item: ShotItem, in visibleItems: [ShotItem]) -> Int? {
        guard let idx = visibleItems.firstIndex(where: { $0.id == item.id }), idx < 9 else { return nil }
        return idx + 1
    }

    public static func targetItem(forShortcut digit: Int, in visibleItems: [ShotItem]) -> ShotItem? {
        guard digit >= 1 && digit <= 9 else { return nil }
        let index = digit - 1
        guard index >= 0 && index < visibleItems.count else { return nil }
        return visibleItems[index]
    }

    public static func stepDown(currentIndex: Int?, visibleCount: Int) -> Int? {
        guard visibleCount > 0 else { return nil }
        guard let current = currentIndex else { return 0 }
        if current < 0 || current >= visibleCount - 1 {
            return 0 // Circular wrap to top
        }
        return current + 1
    }

    public static func stepUp(currentIndex: Int?, visibleCount: Int) -> Int? {
        guard visibleCount > 0 else { return nil }
        guard let current = currentIndex else { return visibleCount - 1 }
        if current <= 0 || current >= visibleCount {
            return visibleCount - 1 // Circular wrap to bottom
        }
        return current - 1
    }

    public static func parseShortcut(from event: NSEvent, searchFieldHasFocus: Bool) -> Int? {
        guard event.type == .keyDown else { return nil }
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let char = chars.first,
              let digit = char.wholeNumberValue,
              digit >= 1 && digit <= 9 else {
            return nil
        }

        let flags = event.modifierFlags
        let hasCommand = flags.contains(.command)
        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)

        guard !hasControl && !hasOption else { return nil }

        if hasCommand {
            return digit
        } else if !searchFieldHasFocus {
            return digit
        }
        return nil
    }
}
