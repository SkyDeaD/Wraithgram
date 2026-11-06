#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSBundle * _Nonnull getAppBundle(void);

// WRAITH: icon packs (WGInterface). An immutable «asset name → image» table published by the
// icon pack resolver; `UIImage(bundleImageName:)` answers from it before the asset catalog.
// WRAITH: no pack — one atomic load per lookup; with a pack — a retain under an unfair lock. A replaced
// table is freed when its last reader is done (WRAITH). `nil` (the default) = Telegram's assets.
void WGAppBundleSetImageOverrides(NSDictionary<NSString *, UIImage *> * _Nullable overrides);

@interface UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName;

@end
