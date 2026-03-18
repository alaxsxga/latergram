import ComposableArchitecture
import LatergramCore
import Foundation

@DependencyClient
struct FriendsCacheClient: Sendable {
    var load: @Sendable (_ userID: UUID) -> [Friend] = { _ in [] }
    var save: @Sendable (_ friends: [Friend], _ userID: UUID) -> Void = { _, _ in }
    var clear: @Sendable (_ userID: UUID) -> Void = { _ in }
}

extension FriendsCacheClient: DependencyKey {
    static let liveValue = FriendsCacheClient(
        load: { userID in
            guard let url = cacheFileURL(userID: userID),
                  let data = try? Data(contentsOf: url),
                  let friends = try? JSONDecoder().decode([Friend].self, from: data)
            else { return [] }
            return friends
        },
        save: { friends, userID in
            guard let url = cacheFileURL(userID: userID),
                  let data = try? JSONEncoder().encode(friends)
            else { return }
            try? data.write(to: url, options: .atomic)
        },
        clear: { userID in
            guard let url = cacheFileURL(userID: userID) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    )
}

private func cacheFileURL(userID: UUID) -> URL? {
    FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("friends_\(userID).json")
}

extension DependencyValues {
    var friendsCacheClient: FriendsCacheClient {
        get { self[FriendsCacheClient.self] }
        set { self[FriendsCacheClient.self] = newValue }
    }
}
