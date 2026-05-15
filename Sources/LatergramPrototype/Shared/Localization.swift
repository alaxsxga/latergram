import SwiftUI

func L(_ key: LocalizedStringKey) -> Text {
    Text(key, bundle: .module)
}

func LS(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
