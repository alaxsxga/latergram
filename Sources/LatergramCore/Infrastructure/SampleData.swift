import Foundation

public enum SampleData {
    public static func friends() -> [Friend] {
        [
            Friend(displayName: "Alice", status: .accepted),
            Friend(displayName: "Ben", status: .accepted),
            Friend(displayName: "Cara", status: .pending)
        ]
    }

    public static func messages(me: UserProfile, friends: [Friend]) -> [DelayedMessage] {
        guard let alice = friends.first(where: { $0.displayName == "Alice" }),
              let ben = friends.first(where: { $0.displayName == "Ben" }) else {
            return []
        }

        return [
            DelayedMessage(
                senderID: alice.id,
                receiverID: me.id,
                senderName: alice.displayName,
                body: "Happy birthday in advance!",
                style: .heart,
                sentAt: Date().addingTimeInterval(-3600),
                unlockAt: Date().addingTimeInterval(4200)
            ),
            DelayedMessage(
                senderID: ben.id,
                receiverID: me.id,
                senderName: ben.displayName,
                body: "You can do it, one step at a time.",
                style: .warm,
                sentAt: Date().addingTimeInterval(-600),
                unlockAt: Date().addingTimeInterval(190)
            ),
            DelayedMessage(
                senderID: alice.id,
                receiverID: me.id,
                senderName: alice.displayName,
                body: "這條訊息已經可以看了，點我開啟！",
                style: .cool,
                sentAt: Date().addingTimeInterval(-50),
                unlockAt: Date().addingTimeInterval(10)
            ),
            DelayedMessage(
                senderID: ben.id,
                receiverID: me.id,
                senderName: ben.displayName,
                body: "早就該讓你看到這句話了。",
                style: .classic,
                sentAt: Date().addingTimeInterval(-3660),
                unlockAt: Date().addingTimeInterval(-60)
            )
        ]
    }
}
