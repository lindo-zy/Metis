//
//  MTCustomJumpManagementViewController.h
//  Mt
//

#import <Preferences/PSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTCustomJumpManagementViewController : PSViewController
+ (BOOL)isImageActionManagement;
+ (NSString *)referenceSlot;
+ (BOOL)prepareSharedActionsWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
