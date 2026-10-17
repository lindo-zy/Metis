//
//  MTRespringControllerSupport.h
//  Mt
//

#import <Preferences/PSListController.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSListController (MTRespringControllerSupport)

- (void)promptToRespring;
- (void)respring;

@end

NS_ASSUME_NONNULL_END
