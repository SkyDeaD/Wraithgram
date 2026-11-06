import Foundation
import UIKit
import TelegramPresentationData
import TelegramUIPreferences
import ChatListTitleView // WRAITH: chat list row style (WGChatListStyleHooks)

public final class ChatListPresentationData {
    public let theme: PresentationTheme
    public let fontSize: PresentationFontSize
    public let strings: PresentationStrings
    public let dateTimeFormat: PresentationDateTimeFormat
    public let nameSortOrder: PresentationPersonNameOrder
    public let nameDisplayOrder: PresentationPersonNameOrder
    public let disableAnimations: Bool
    // WRAITH: the look of the rows, taken once per presentation data (WGChatListStyleHooks.rowStyle)
    public let wgRowStyle: WGChatListRowStyle
    
    public init(theme: PresentationTheme, fontSize: PresentationFontSize, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, nameSortOrder: PresentationPersonNameOrder, nameDisplayOrder: PresentationPersonNameOrder, disableAnimations: Bool) {
        self.theme = theme
        self.fontSize = fontSize
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.nameSortOrder = nameSortOrder
        self.nameDisplayOrder = nameDisplayOrder
        self.disableAnimations = disableAnimations
        self.wgRowStyle = wgChatListRowStyle() // WRAITH: see the property
    }
}
