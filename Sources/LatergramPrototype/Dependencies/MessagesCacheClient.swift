import ComposableArchitecture
import LatergramCore
import Foundation

@DependencyClient
struct MessagesCacheClient: Sendable {
    var load: @Sendable (_ userID: UUID, _ friendID: UUID) -> [DelayedMessage] = { _, _ in [] }
    var save: @Sendable (_ messages: [DelayedMessage], _ userID: UUID, _ friendID: UUID) -> Void = { _, _, _ in }
    var clear: @Sendable (_ userID: UUID) -> Void = { _ in }
}

extension MessagesCacheClient: DependencyKey {
    static let liveValue = MessagesCacheClient(
        load: { userID, friendID in
            guard let url = threadCacheFileURL(userID: userID, friendID: friendID),
                  let data = try? Data(contentsOf: url),
                  let messages = try? JSONDecoder().decode([DelayedMessage].self, from: data)
            else { return [] }
            return messages
        },
        save: { messages, userID, friendID in
            guard let url = threadCacheFileURL(userID: userID, friendID: friendID),
                  let data = try? JSONEncoder().encode(messages)
            else { return }
            try? data.write(to: url, options: .atomic)
        },
        clear: { userID in
            guard let dir = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask).first
            else { return }
            let prefix = "thread_\(userID)_"
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files where file.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    )
}

private func threadCacheFileURL(userID: UUID, friendID: UUID) -> URL? {
    FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("thread_\(userID)_\(friendID).json")
}

extension DependencyValues {
    var messagesCacheClient: MessagesCacheClient {
        get { self[MessagesCacheClient.self] }
        set { self[MessagesCacheClient.self] = newValue }
    }
}
