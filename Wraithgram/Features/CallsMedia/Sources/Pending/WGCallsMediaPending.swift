import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatListUI
import WGCore
import WGHooks

// Registrations on the points that requests R1 and R2 of this zone add to the frozen WGHooks
// (`WGChatListHooks.accessoryPeers`, `WGGalleryHooks.videoItemDidLoad/videoItemDidLayout`). This directory is the only part of the module that needs them; if
// the requests wait, exclude `Sources/Pending/**` in BUILD and drop the one
// `WGCallsMediaPending.register()` call — the rest of the zone compiles without them (download status
// then shows the line only for rows laid out after a download started; subtitles have no host).

enum WGCallsMediaPending {
    static func register() {
        // R1: chats with a download — their rows re-lay out when it starts or ends, never per percent.
        WGChatListHooks.accessoryPeers.register({ context in
            let service = WGDownloadStatusService.service(for: context)
            return combineLatest(service.activePeers, WGCallsMediaSettings.statusInChatList.signal)
            |> map { peers, enabled -> Set<EnginePeer.Id> in
                return enabled ? peers : Set()
            }
        })

        // R2: the gallery's video items host the subtitles line.
        WGGalleryHooks.videoItemDidLoad.register({ item in
            WGSubtitlesFeature.videoItemDidLoad(context: item.context, message: item.message, file: item.file, itemNode: item.itemNode, status: item.status)
        })
        WGGalleryHooks.videoItemDidLayout.register({ layout in
            WGSubtitlesFeature.videoItemDidLayout(itemNode: layout.itemNode, size: layout.size, bottomInset: layout.bottomInset, transition: layout.transition)
        })
    }
}
