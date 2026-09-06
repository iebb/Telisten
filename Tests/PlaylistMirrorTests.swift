import Foundation

@main
enum PlaylistMirrorTests {
    static func main() throws {
        precondition(PlaylistFolderConfiguration.defaultName == "_Playlist")
        precondition(PlaylistFolderConfiguration.normalizedName("  我的歌单  ") == "我的歌单")
        precondition(PlaylistFolderConfiguration.normalizedName("Music 🎵") == "Music 🎵")
        precondition(PlaylistFolderConfiguration.normalizedName("123456789012") != nil)
        for invalid in ["", "   ", "1234567890123", "my\nplaylists", "my\tplaylists"] {
            precondition(PlaylistFolderConfiguration.normalizedName(invalid) == nil)
        }
        let local = MusicChat(id: "c:1", peerID: 1, accessHash: 2, kind: .channel, title: "New playlist", username: nil)
        let remote = MusicChat(id: "c:2", peerID: 2, accessHash: 3, kind: .channel, title: "Existing playlist", username: nil)
        let mirror = LocalPlaylistMirror(
            playlists: [local, remote],
            unfiledPlaylistIDs: [local.id],
            pendingCreationIDs: [local.id]
        )
        let restored = try JSONDecoder().decode(LocalPlaylistMirror.self, from: JSONEncoder().encode(mirror))
        precondition(restored.pendingCreationIDs?.contains(local.id) == true,
                     "A retry after restart must recognize the already-created channel")
        precondition(restored.mergingFolderPlaylists([]) == [local],
                     "No _Playlist folder must not erase an unfiled playlist")
        let merged = restored.mergingFolderPlaylists([remote])
        precondition(Set(merged.map(\.id)) == [local.id, remote.id],
                     "Folder refresh must retain playlists created while the folder was full")

        var renamed = local
        renamed.title = "Renamed in Telegram"
        let synchronized = restored.mergingFolderPlaylists([renamed, remote])
        precondition(synchronized.count == 2)
        precondition(synchronized.first(where: { $0.id == local.id })?.title == renamed.title,
                     "Remote metadata must win after folder membership becomes available")

        let oldJSON = Data(#"{"playlists":[],"tracksByPlaylist":{},"trackOrders":{}}"#.utf8)
        let oldMirror = try JSONDecoder().decode(LocalPlaylistMirror.self, from: oldJSON)
        precondition(oldMirror.unfiledPlaylistIDs == nil)
        precondition(oldMirror.pendingCreationIDs == nil)
        precondition(oldMirror.mergingFolderPlaylists([remote]) == [remote])
        print("PASS: folder-capacity fallback, persistence, retry identity, remote merge, existing mirror decoding")
    }
}
