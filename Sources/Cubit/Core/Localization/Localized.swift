import Foundation

/// Cubit uses two key conventions, on purpose.
///
/// SwiftUI's `Text`, `Button`, `Toggle`, `.help` and `.accessibilityLabel` take a
/// `LocalizedStringKey` and look the ENGLISH LITERAL up in `Bundle.main` for free — so those call
/// sites stay plain English source and the `.strings` files key on that English. Nothing to wrap.
///
/// Everything AppKit and Core touch — `NSMenu` titles, toasts, VoiceOver announcements, the export
/// vocabulary — is a plain `String` that no framework localizes. Those go through `localized(_:_:_:)`
/// with a DOTTED key, because their English text is often a format string (`"%1$@ of %2$@ area"`)
/// that makes a terrible key, and because the `value:` fallback means a missing translation shows
/// English rather than leaking `a11y.value.rectangle` into the interface.
func localized(_ key: String, _ english: String, _ comment: String = "", bundle: Bundle = .main) -> String {
    NSLocalizedString(key, tableName: nil, bundle: bundle, value: english, comment: comment)
}

/// A localized format string applied to its arguments. Format strings are positional so a
/// translator can reorder them; `String(format:)` honours `%1$@`-style specifiers.
func localizedFormat(_ key: String, _ english: String, _ comment: String = "", bundle: Bundle = .main, _ arguments: CVarArg...) -> String {
    String(format: localized(key, english, comment, bundle: bundle), arguments: arguments)
}

/// A localized string chosen by count, via `Localizable.stringsdict`. English needs only
/// one/other; Russian and Arabic need up to six, and the `.stringsdict` is the only thing that
/// can express that — a `count == 1 ? :` ternary in Swift silently gets those languages wrong.
///
/// `english` is the `%#@...@`-free fallback used when no `.stringsdict` entry exists.
func localizedCount(_ key: String, _ english: String, _ comment: String = "", bundle: Bundle = .main, count: Int, locale: Locale = .current) -> String {
    let format = NSLocalizedString(key, tableName: nil, bundle: bundle, value: english, comment: comment)
    return String(format: format, locale: locale, count)
}
