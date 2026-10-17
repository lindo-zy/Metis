//
//  MTClearConfirmationViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTClearConfirmationView;
@class MTClearConfirmationViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol MTClearConfirmationViewControllerDelegate <NSObject>

- (void)clearConfirmationViewControllerDidCancel:(MTClearConfirmationViewController *)controller;
- (void)clearConfirmationViewControllerDidClearHistoryKey:(NSString *)historyKey;
- (void)clearConfirmationViewController:(MTClearConfirmationViewController *)controller
              didFailClearingHistoryKey:(NSString *)historyKey;

@end

@interface MTClearConfirmationViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTClearConfirmationViewControllerDelegate> delegate;
@property(nonatomic, copy, nullable) NSString *historyKey;
@property(nonatomic, assign, getter=isImagesOnly) BOOL imagesOnly;
@property(nonatomic, strong, readonly) MTClearConfirmationView *confirmationView;

- (void)beginWithHistoryKey:(NSString *)historyKey;
- (void)beginWithHistoryKey:(NSString *)historyKey imagesOnly:(BOOL)imagesOnly;
- (void)handleCancel;
- (void)handleConfirm;

@end

NS_ASSUME_NONNULL_END
