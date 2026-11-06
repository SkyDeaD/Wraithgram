// Compiled into TabBarComponent (filegroup //Wraithgram/Features/Interface:TabBarComponentPointSources),
// used by TabBarComponent and TabBarUI. Owner: W2-5 (tab bar organizer, labels, wide bar, height).
// One style snapshot per layout of the bar; no reads per item.

import Foundation
import UIKit
import WGCore

/// How the main tab bar looks. `.upstream` = Telegram's bar.
public struct WGTabBarStyle: Equatable {
    public var hidesTitles: Bool
    /// No 500 pt cap and narrow side insets.
    public var isWide: Bool
    /// The narrow bar of Swiftgram / the old Wraithgram («Широкая панель» off): as wide as its tabs
    /// need — fewer tabs, a narrower bar — instead of Telegram's stretching over the whole width
    /// (`wgTabBarAvailableWidth`). Off for Telegram's own bars (`.upstream`).
    public var fitsItems: Bool
    /// The bar is taken off the screen (the app's own hide requests still work on top).
    public var hidesBar: Bool
    /// Extra height of the items, pt.
    public var heightOffset: CGFloat
    /// Lift of the bar above the bottom edge, pt.
    public var bottomOffset: CGFloat
    /// Changes whenever own labels change, so cached layouts of the bar refresh.
    public var titlesRevision: Int

    public init(hidesTitles: Bool, isWide: Bool, fitsItems: Bool, hidesBar: Bool, heightOffset: CGFloat, bottomOffset: CGFloat, titlesRevision: Int) {
        self.hidesTitles = hidesTitles
        self.isWide = isWide
        self.fitsItems = fitsItems
        self.hidesBar = hidesBar
        self.heightOffset = heightOffset
        self.bottomOffset = bottomOffset
        self.titlesRevision = titlesRevision
    }

    public static let upstream = WGTabBarStyle(hidesTitles: false, isWide: false, fitsItems: false, hidesBar: false, heightOffset: 0.0, bottomOffset: 0.0, titlesRevision: 0)

    /// Height of a tab before `heightOffset`: Telegram's 56 pt, or 40 pt without labels — the compact
    /// bar of Swiftgram / the old Wraithgram (`showTabNames` off), 48 pt with its glass inset.
    public var baseItemHeight: CGFloat {
        return self.hidesTitles ? 40.0 : 56.0
    }
}

/// The width the bar lays its tabs out in. A narrow bar (`fitsItems`) is Swiftgram's: four tabs
/// keep the width, three get 80 % of it, two 67 %, one 57 %; without the search button it is also
/// that button's width narrower (nothing in this Telegram shows it, so always). The open search
/// field always gets the whole width.
public func wgTabBarAvailableWidth(_ width: CGFloat, style: WGTabBarStyle, itemCount: Int, hasSearch: Bool, isSearchActive: Bool, searchButtonWidth: CGFloat) -> CGFloat {
    if !style.fitsItems || isSearchActive {
        return width
    }
    let reducer: CGFloat
    switch itemCount {
    case 1:
        reducer = 1.75
    case 2:
        reducer = 1.5
    case 3:
        reducer = 1.25
    default:
        reducer = 1.0
    }
    var result = floor(width / reducer)
    if !hasSearch {
        result -= searchButtonWidth
    }
    return max(0.0, result)
}

public enum WGTabBarHooks {
    /// Provider of the style (first registered wins). Main thread, once per layout of the bar.
    public static let style = WGHookPoint<() -> WGTabBarStyle>("tabBar.style")

    /// Policy: an own label for a tab's item (nil = the controller's title). Main thread.
    public static let itemTitle = WGHookPoint<(UITabBarItem) -> String?>("tabBar.itemTitle")
}

/// The current style of the bar.
public func wgTabBarStyle() -> WGTabBarStyle {
    if WGTabBarHooks.style.isEmpty {
        return .upstream
    }
    return WGTabBarHooks.style.handlers[0]()
}

/// The label of a tab's item: an own label or Telegram's.
public func wgTabBarItemTitle(_ item: UITabBarItem) -> String? {
    if WGTabBarHooks.itemTitle.isEmpty {
        return item.title
    }
    for handler in WGTabBarHooks.itemTitle.handlers {
        if let value = handler(item) {
            return value
        }
    }
    return item.title
}
