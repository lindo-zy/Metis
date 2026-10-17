#import <Foundation/Foundation.h>

@interface DXPrefsManager : NSObject
@property(nonatomic, strong) NSDictionary *prefs;
/// YES only after this process has loaded a complete preference snapshot.
/// Sandboxed hosts keep this false when the shared snapshot cannot be read, so
/// callers never mistake an IPC/file-access failure for a fresh installation.
@property(nonatomic, assign, readonly) BOOL preferencesAvailable;
+ (instancetype)sharedInstance;
+ (BOOL)isRunningInSandbox;
-(NSDictionary *)readPrefs;
-(NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox;
-(void)writePrefs:(NSDictionary *)dictionary;
-(void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(void)setValue:(id)value forKey:(NSString *)key;
-(id)getValueForKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(id)getValueForKey:(NSString *)key;
-(void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(void)removeKey:(NSString *)key;
/// Removes a key and optionally broadcasts the cross-process preferences notification.
/// Internal cache maintenance must use notify:NO to avoid re-entering the reload callback.
-(void)removeKey:(NSString *)key notify:(BOOL)notify;
-(void)reload;
-(void)postChangedNotification;
@end
