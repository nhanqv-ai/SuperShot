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

    // MARK: - Differentiated Section Shortcuts (v1.0.19)

    /// Target section for differentiated shortcuts.
    public enum ShortcutSection: Sendable, Equatable {
        case pinned
        case recent
    }

    /// Evaluates an NSEvent to determine section-aware shortcut:
    /// - Option + 1..9: target pinned items
    /// - Command + 1..9: target normal / recent history items
    /// - Bare 1..9 (when search field is not focused): target normal / recent history items
    public static func parseSectionShortcut(
        from event: NSEvent,
        searchFieldHasFocus: Bool
    ) -> (section: ShortcutSection, digit: Int)? {
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

        // Ignore if Control modifier is active
        guard !hasControl else { return nil }

        if hasOption && !hasCommand {
            return (.pinned, digit)
        } else if hasCommand && !hasOption {
            return (.recent, digit)
        } else if !hasOption && !hasCommand && !searchFieldHasFocus {
            return (.recent, digit)
        }

        return nil
    }

    /// Resolves the target item for a section shortcut.
    public static func targetItem(
        forSectionShortcut resolved: (section: ShortcutSection, digit: Int),
        pinnedItems: [ShotItem],
        recentItems: [ShotItem]
    ) -> ShotItem? {
        let index = resolved.digit - 1
        guard index >= 0 else { return nil }

        switch resolved.section {
        case .pinned:
            guard index < pinnedItems.count else { return nil }
            return pinnedItems[index]
        case .recent:
            guard index < recentItems.count else { return nil }
            return recentItems[index]
        }
    }

    /// Resolves the display badge for an item based on its section and position.
    /// Pinned items: ⌥1..⌥9
    /// Recent items: 1..9
    public static func badgeString(
        for item: ShotItem,
        pinnedItems: [ShotItem],
        recentItems: [ShotItem]
    ) -> String? {
        if let pinnedIdx = pinnedItems.firstIndex(where: { $0.id == item.id }), pinnedIdx < 9 {
            return "⌥\(pinnedIdx + 1)"
        }
        if let recentIdx = recentItems.firstIndex(where: { $0.id == item.id }), recentIdx < 9 {
            return "\(recentIdx + 1)"
        }
        return nil
    }
}
