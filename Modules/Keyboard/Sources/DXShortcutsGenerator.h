#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#define DX_ROOT_PATH_NS(path) jbroot(path)
#else
#import <rootless.h>
#define DX_ROOT_PATH_NS(path) ROOT_PATH_NS(path)
#endif

@interface DXShortcutsGenerator : NSObject
+(void)load;
+(BOOL)isAvailableShortcutSelector:(NSString *)selector;
+(BOOL)isVisibleShortcutSelector:(NSString *)selector;
+(BOOL)isShellXScreenshotAvailable;
+(BOOL)isPixPinScreenshotAvailable;
+(BOOL)isKayokoInstalled;
+(BOOL)isPullOverXInstalled;
+(instancetype)sharedInstance;
-(instancetype)init;
-(NSArray *)imageNameArrayForiOS:(NSInteger)iosVersion;
-(NSArray *)selectorNames;
-(NSArray *)labelName;
-(NSArray *)shortenedlabelName;
// 选择动作页的内置动作分组：返回组顺序与 selector→组 id（未映射归 tools）。
+(NSArray<NSString *> *)builtInActionGroupOrder;
+(NSString *)builtInActionGroupForSelector:(NSString *)selector;
@end
