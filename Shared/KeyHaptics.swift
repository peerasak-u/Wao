import Foundation
import WaoCore

/// Whether the keyboard taps on a key press. The app writes it and the keyboard reads it, through the App Group.
/// A keyboard cannot read the system's own keyboard haptics switch, so เว่า keeps its own. It is off by default, as the system keyboard's is.
enum KeyHaptics {
    static let key = "keyHaptics"
    static let store = UserDefaults(suiteName: Bridge.appGroup)

    static var isOn: Bool { store?.object(forKey: key) as? Bool ?? false }
}
