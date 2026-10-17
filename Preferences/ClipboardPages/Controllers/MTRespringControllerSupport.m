//
//  MTRespringControllerSupport.m
//  Mt
//

#import "MTRespringControllerSupport.h"

#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, SBSRelaunchActionOptions) {
    SBSRelaunchActionOptionsNone,
    SBSRelaunchActionOptionsRestartRenderServer = 1 << 0,
    SBSRelaunchActionOptionsSnapshotTransition = 1 << 1,
    SBSRelaunchActionOptionsFadeToBlackTransition = 1 << 2
};

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason
                         options:(SBSRelaunchActionOptions)options
                       targetURL:(nullable NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(nullable void (^)(NSError *error))result;
@end

static BOOL mtSendRelaunchActionWithOptions(SBSRelaunchActionOptions options, NSString *actionName) {
    Class actionClass = NSClassFromString(@"SBSRelaunchAction");
    Class serviceClass = NSClassFromString(@"FBSSystemService");
    if (![actionClass respondsToSelector:@selector(actionWithReason:options:targetURL:)] ||
        ![serviceClass respondsToSelector:@selector(sharedService)]) {
        NSLog(@"Mt: Unable to perform %@ because FrontBoard relaunch SPI is unavailable",
              actionName ?: @"relaunch");
        return NO;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSURL *mtClipboardURL = [NSURL URLWithString:@"prefs:root=Mt"];
      SBSRelaunchAction *action = [(id)actionClass actionWithReason:@"Metis" options:options targetURL:mtClipboardURL];
      FBSSystemService *service = [(id)serviceClass sharedService];
      if (!action || ![service respondsToSelector:@selector(sendActions:withResult:)]) {
          NSLog(@"Mt: FBSSystemService cannot perform %@", actionName ?: @"relaunch");
          return;
      }

      [service sendActions:[NSSet setWithObject:action]
                withResult:^(NSError *error) {
                  if (error) {
                      NSLog(@"Mt: %@ failed: %@", actionName ?: @"Relaunch", error);
                  }
                }];
    });
    return YES;
}

@implementation PSListController (MTRespringControllerSupport)

- (void)promptToRespring {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *resetAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"MetisClipboard" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:@"This option requires restarting SpringBoard to apply. "
                                                               @"Do you want to restart now?"
                                                         value:nil
                                                         table:@"Root"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Respring Now"
                                                                                           value:nil
                                                                                           table:@"Root"]
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction *action) {
                                                             [self respring];
                                                           }];

    UIAlertAction *notNowAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Not Now"
                                                                                         value:nil
                                                                                         table:@"Root"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [resetAlert addAction:respringAction];
    [resetAlert addAction:notNowAction];

    [self presentViewController:resetAlert animated:YES completion:nil];
}

- (void)respring {
    mtSendRelaunchActionWithOptions(SBSRelaunchActionOptionsRestartRenderServer, @"Hard respring");
}

@end
