import Foundation

enum LegalURLs {
    // Before App Store listing: shows search results for "Latergram"
    // After listing: replace with itms-apps://apps.apple.com/app/id<numeric-id>
    static let appStore = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?term=Latergram")!
    static let privacyPolicy = URL(
        string: "https://veil-basement-18a.notion.site/Latergram-Privacy-Policy-36d10a19957980bcb410f9f20a43c7d9"
    )!
    static let termsOfUse = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
}
