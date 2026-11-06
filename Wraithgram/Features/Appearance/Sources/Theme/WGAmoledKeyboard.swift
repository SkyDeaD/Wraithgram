import Foundation
import UIKit
import ObjectiveC
import SwiftSignalKit
import WGAppearanceSettings

/// «AMOLED-клавиатура», the system keyboard itself. Up to build 199 the switch only set the theme's
/// `keyboardColor` to `.dark` (and only in a dark theme) — the keyboard stayed the system's dark grey
/// glass: «не воркает». The owner's tweak (2026-11-01), done the same way:
///
///     %hook UITextField / UITextView  -becomeFirstResponder → keyboardAppearance = .dark
///     %hook UIKBBackdropView          -layoutSubviews       → backgroundColor = black
///
/// The keyboard appearance is read when a field becomes first responder, so every field — Telegram's
/// themed inputs and plain UIKit ones (alerts, search) — asks for the dark keyboard there.
/// `UIKBBackdropView` (`UIVisualEffectView`; `UIKBVisualEffectView` is its subclass) has no
/// `layoutSubviews` of its own in UIKit 27: one is added that calls the inherited one first, as Logos
/// does. The methods are replaced once, on the first switch-on; while the switch is off they only
/// call the original (and give a backdrop painted earlier its own color back).
enum WGAmoledKeyboard {
    /// Main thread.
    fileprivate static var isEnabled = false
    private static var isInstalled = false
    private static var settingDisposable: Disposable?

    static func register() {
        WGAmoledKeyboard.settingDisposable = (WGAppearanceSettings.amoledKeyboard.signal
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { enabled in
            WGAmoledKeyboard.isEnabled = enabled
            if enabled {
                WGAmoledKeyboard.installIfNeeded()
            }
        })
    }

    private static func installIfNeeded() {
        if WGAmoledKeyboard.isInstalled {
            return
        }
        WGAmoledKeyboard.isInstalled = true
        WGAmoledKeyboard.hookBecomeFirstResponder(UITextField.self)
        WGAmoledKeyboard.hookBecomeFirstResponder(UITextView.self)
        if let backdropClass = NSClassFromString("UIKBBackdropView") {
            WGAmoledKeyboard.hookBackdropLayout(backdropClass)
        }
    }

    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
    private typealias VoidIMP = @convention(c) (AnyObject, Selector) -> Void

    /// The class's own method for `selector`, nil when it is only inherited.
    private static func ownMethod(_ cls: AnyClass, _ selector: Selector) -> Method? {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return nil
        }
        defer {
            free(methods)
        }
        for index in 0 ..< Int(count) where method_getName(methods[index]) == selector {
            return methods[index]
        }
        return nil
    }

    private static func hookBecomeFirstResponder(_ cls: AnyClass) {
        let selector = #selector(UIResponder.becomeFirstResponder)
        guard let inherited = class_getInstanceMethod(cls, selector) else {
            return
        }
        let ownMethod = WGAmoledKeyboard.ownMethod(cls, selector)
        let original = unsafeBitCast(method_getImplementation(ownMethod ?? inherited), to: BoolIMP.self)
        let block: @convention(block) (AnyObject) -> Bool = { object in
            if WGAmoledKeyboard.isEnabled {
                if let textField = object as? UITextField, textField.keyboardAppearance != .dark {
                    textField.keyboardAppearance = .dark
                } else if let textView = object as? UITextView, textView.keyboardAppearance != .dark {
                    textView.keyboardAppearance = .dark
                }
            }
            return original(object, selector)
        }
        let implementation = imp_implementationWithBlock(block)
        if let ownMethod {
            method_setImplementation(ownMethod, implementation)
        } else {
            class_addMethod(cls, selector, implementation, method_getTypeEncoding(inherited))
        }
    }

    private static var paintedColorKey: UInt8 = 0

    private static func hookBackdropLayout(_ cls: AnyClass) {
        let selector = #selector(UIView.layoutSubviews)
        guard let superclass = class_getSuperclass(cls), let inherited = class_getInstanceMethod(cls, selector) else {
            return
        }
        let ownMethod = WGAmoledKeyboard.ownMethod(cls, selector)
        let ownOriginal = ownMethod.map { unsafeBitCast(method_getImplementation($0), to: VoidIMP.self) }
        let block: @convention(block) (AnyObject) -> Void = { object in
            if let ownOriginal {
                ownOriginal(object, selector)
            } else if let superImplementation = class_getMethodImplementation(superclass, selector) {
                // The added override: the inherited layout first, looked up now (another hook may
                // have replaced it since).
                unsafeBitCast(superImplementation, to: VoidIMP.self)(object, selector)
            }
            guard let view = object as? UIView else {
                return
            }
            WGAmoledKeyboard.paint(view)
        }
        let implementation = imp_implementationWithBlock(block)
        if let ownMethod {
            method_setImplementation(ownMethod, implementation)
        } else {
            class_addMethod(cls, selector, implementation, method_getTypeEncoding(inherited))
        }
    }

    /// Black while the switch is on; the backdrop's own color back once it is off.
    private static func paint(_ view: UIView) {
        let painted = objc_getAssociatedObject(view, &WGAmoledKeyboard.paintedColorKey)
        if WGAmoledKeyboard.isEnabled {
            if painted == nil {
                objc_setAssociatedObject(view, &WGAmoledKeyboard.paintedColorKey, view.backgroundColor ?? NSNull(), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            if view.backgroundColor != UIColor.black {
                view.backgroundColor = UIColor.black
            }
        } else if let painted {
            objc_setAssociatedObject(view, &WGAmoledKeyboard.paintedColorKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            view.backgroundColor = painted as? UIColor
        }
    }
}
