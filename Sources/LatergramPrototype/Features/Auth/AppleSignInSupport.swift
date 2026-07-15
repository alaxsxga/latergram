#if os(iOS)
import CryptoKit
import Foundation

// Sign in with Apple 需要 nonce 防重放：
//   1. 產生一組隨機 raw nonce。
//   2. 把 sha256(raw) 塞進 ASAuthorizationAppleIDRequest.nonce（Apple 會把它寫進 idToken）。
//   3. 登入時把「raw nonce」交給 Supabase signInWithIdToken，
//      server 端自行 sha256 後和 idToken 內的值比對。
// 所以 request 用 hash、Supabase 用 raw，兩者不可搞混。
enum AppleSignIn {
    /// 產生一組 URL-safe 的隨機 nonce（原始值，交給 Supabase 用）。
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    /// 對 raw nonce 取 SHA256 hex（塞進 Apple request 的值）。
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
