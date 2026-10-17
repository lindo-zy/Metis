#import "MTLog.h"
#import <sys/syslog.h>

NSString *const MTCoreVersionString = @METIS_PACKAGE_VERSION;

NSString *const MTLogModuleCore = @"core";
NSString *const MTLogModuleCapture = @"capture";
NSString *const MTLogModuleKeyboard = @"keyboard";
NSString *const MTLogModuleClipboard = @"clipboard";
NSString *const MTLogModulePrefs = @"prefs";

static void MTLogV(int priority, NSString *module, NSString *format, va_list args) {
    if (!format) return;
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    NSString *line = [NSString stringWithFormat:@"[Metis][%@] %@", module ?: @"?", body];
    syslog(priority, "%s", line.UTF8String);
}

void MTLogInfo(NSString *module, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    MTLogV(LOG_INFO, module, format, args);
    va_end(args);
}

void MTLogWarn(NSString *module, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    MTLogV(LOG_WARNING, module, format, args);
    va_end(args);
}

void MTLogError(NSString *module, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    MTLogV(LOG_ERR, module, format, args);
    va_end(args);
}
