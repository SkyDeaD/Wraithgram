#import <AppBundle/AppBundle.h>
#import <stdatomic.h>
#import <os/lock.h> // WRAITH: icon packs (the table's lock)

// WRAITH: icon packs — see WGAppBundleSetImageOverrides in AppBundle.h. While no pack is enabled a
// lookup is one atomic load of a flag. Otherwise a reader takes a strong reference to the current
// immutable table under an unfair lock (held for a retain only) and looks it up outside the lock;
// the writer swaps the table under the same lock. A replaced table is freed once its last reader is
// done — the old code kept every table it had ever published (up to ~400 images each) alive forever.
static atomic_bool wgHasImageOverrides = false;
static os_unfair_lock wgImageOverridesLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, UIImage *> *wgImageOverrides = nil;

// WRAITH: icon packs — swaps the published table, returns the replaced one.
static NSDictionary<NSString *, UIImage *> * _Nullable wgSwapImageOverrides(NSDictionary<NSString *, UIImage *> * _Nullable table) {
    os_unfair_lock_lock(&wgImageOverridesLock);
    NSDictionary *previous = wgImageOverrides;
    wgImageOverrides = table;
    atomic_store_explicit(&wgHasImageOverrides, table != nil, memory_order_release);
    os_unfair_lock_unlock(&wgImageOverridesLock);
    return previous;
}

void WGAppBundleSetImageOverrides(NSDictionary<NSString *, UIImage *> * _Nullable overrides) {
    NSDictionary *table = overrides.count != 0 ? [overrides copy] : nil;
    // WRAITH: the replaced table is released here, outside the lock (or later, by the last reader holding it).
    (void)wgSwapImageOverrides(table);
}

// WRAITH: icon packs — the current table, retained for the caller; nil while no pack is enabled.
static NSDictionary<NSString *, UIImage *> * _Nullable wgCurrentImageOverrides(void) {
    if (!atomic_load_explicit(&wgHasImageOverrides, memory_order_acquire)) {
        return nil;
    }
    NSDictionary *table = nil;
    os_unfair_lock_lock(&wgImageOverridesLock); // WRAITH: held for a retain only
    table = wgImageOverrides;
    os_unfair_lock_unlock(&wgImageOverridesLock);
    return table;
}

NSBundle * _Nonnull getAppBundle() {
    static NSBundle *appBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        if ([[bundle.bundleURL pathExtension] isEqualToString:@"appex"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([[bundle.bundleURL pathExtension] isEqualToString:@"framework"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([[bundle.bundleURL pathExtension] isEqualToString:@"Frameworks"]) {
            bundle = [NSBundle bundleWithURL:[bundle.bundleURL URLByDeletingLastPathComponent]];
        }
        appBundle = bundle;
    });
    
    return appBundle;
}

@implementation UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName {
    NSDictionary<NSString *, UIImage *> *overrides = wgCurrentImageOverrides(); // WRAITH: icon packs
    if (overrides != nil) {
        UIImage *image = overrides[bundleImageName];
        if (image != nil) {
            return image;
        }
    }
    return [UIImage imageNamed:bundleImageName inBundle:getAppBundle() compatibleWithTraitCollection:nil];
}

@end
