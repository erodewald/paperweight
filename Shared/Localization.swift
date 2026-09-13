import Foundation

/// Where localized strings are looked up. The app and its extensions use their
/// own main bundle, which carries the shared catalog. Unit tests have no host
/// app, so they point this at the test bundle in `setUp`.
enum L10n {
    static var bundle: Bundle = .main
}
