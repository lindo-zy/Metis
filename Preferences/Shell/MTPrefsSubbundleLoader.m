#import "MTPrefsSubbundleLoader.h"
#import "MTPathResolver.h"
#import "MTLog.h"

NSString *const MTPrefsSubbundleLoaderErrorDomain = @"com.lindo.metis.prefs.subbundle";

@implementation MTPrefsSubbundleLoader

+ (Class)loadControllerClassFromBundle:(NSString *)bundleName
                            classNamed:(NSString *)controllerName
                                 error:(NSError **)error {
    NSString *path = MTResolvePath(
        [NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", bundleName]);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:MTPrefsSubbundleLoaderErrorDomain code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"subbundle not installed"}];
        return nil;
    }
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (![bundle load]) {
        if (error) *error = [NSError errorWithDomain:MTPrefsSubbundleLoaderErrorDomain code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"subbundle load failed"}];
        return nil;
    }
    Class controllerClass = [bundle classNamed:controllerName] ?: NSClassFromString(controllerName);
    if (!controllerClass) {
        if (error) *error = [NSError errorWithDomain:MTPrefsSubbundleLoaderErrorDomain code:3
                                            userInfo:@{NSLocalizedDescriptionKey: @"controller class missing"}];
        return nil;
    }
    return controllerClass;
}

@end
