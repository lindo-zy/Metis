#import "common.h"
#import "DXServer.h"

@implementation DXServer
+ (void)load {
    @autoreleasepool {
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        
        if (args.count != 0) {
            NSString *executablePath = args[0];
            
            if (executablePath) {
                NSString *processName = [executablePath lastPathComponent];
                
                BOOL isSpringBoard = [processName isEqualToString:@"SpringBoard"];
                
                if (isSpringBoard) {
                    [self sharedInstance];
                    
                }
            }
        }
    }
}

+ (instancetype)sharedInstance {
    static dispatch_once_t once = 0;
    __strong static id sharedInstance = nil;
    dispatch_once(&once, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
    }

    return self;
}

-(NSDictionary *)runCommand:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    NSString *cmd = userInfo[@"value"];
    if ([cmd length] != 0){
        DXRunShellCommand(cmd);
    }
    return nil;

}
@end
