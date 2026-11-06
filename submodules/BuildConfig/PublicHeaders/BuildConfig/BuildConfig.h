#import <Foundation/Foundation.h>

@interface DeviceSpecificEncryptionParameters : NSObject

@property (nonatomic, strong) NSData * _Nonnull key;
@property (nonatomic, strong) NSData * _Nonnull salt;

@end

@interface BuildConfig : NSObject

- (instancetype _Nonnull)initWithBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId;

@property (nonatomic, strong, readonly) NSString * _Nullable appCenterId;
@property (nonatomic, readonly) int32_t apiId;
@property (nonatomic, strong, readonly) NSString * _Nonnull apiHash;
@property (nonatomic, readonly) bool isInternalBuild;
@property (nonatomic, readonly) bool isAppStoreBuild;
@property (nonatomic, readonly) int64_t appStoreId;
@property (nonatomic, strong, readonly) NSString * _Nonnull appSpecificUrlScheme;
@property (nonatomic, readonly) bool isICloudEnabled;
@property (nonatomic, readonly) bool isSiriEnabled;

+ (NSString * _Nullable)keychainAccessGroupForBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId NS_SWIFT_NAME(keychainAccessGroup(baseAppBundleId:));

// WRAITH: the app group to open. "group.<base bundle id>" unless the Info.plist names one (WGAppGroup) or the
// app was re-signed with a profile whose groups are named differently (a purchased certificate re-signed on
// the device): then the first group of embedded.mobileprovision that the system lets the process open.
+ (NSString * _Nonnull)appGroupNameForBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId NS_SWIFT_NAME(appGroupName(baseAppBundleId:));
// WRAITH: the passcode's private keychain group; it must end with the app group without "group." (PasscodeCore).
+ (NSString * _Nullable)passcodePrivateAccessGroupForBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId NS_SWIFT_NAME(passcodePrivateAccessGroup(baseAppBundleId:));

+ (DeviceSpecificEncryptionParameters * _Nonnull)deviceSpecificEncryptionParameters:(NSString * _Nonnull)rootPath baseAppBundleId:(NSString * _Nonnull)baseAppBundleId;
- (NSData * _Nullable)bundleDataWithAppToken:(NSData * _Nullable)appToken tokenType:(NSString * _Nullable)tokenType tokenEnvironment:(NSString * _Nullable)tokenEnvironment signatureDict:(NSDictionary * _Nullable)signatureDict;

+ (void)getHardwareEncryptionAvailableWithBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^ _Nonnull)(NSData * _Nullable))completion;
+ (void)encryptApplicationSecret:(NSData * _Nonnull)secret baseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^ _Nonnull)(NSData * _Nullable, NSData * _Nullable))completion;
+ (void)decryptApplicationSecret:(NSData * _Nonnull)secret publicKey:(NSData * _Nonnull)publicKey baseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^ _Nonnull)(NSData * _Nullable, bool))completion;

@end
