//
//  MTSearchTokenListViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTSearchCriteria;
@class MTSearchToken;
@class MTSearchTokenListViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol MTSearchTokenListViewControllerDelegate <NSObject>

- (void)searchTokenListViewController:(MTSearchTokenListViewController *)controller
                       didSelectToken:(MTSearchToken *)token;

@end

@interface MTSearchTokenListViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTSearchTokenListViewControllerDelegate> delegate;
@property(nonatomic, copy, nullable) void (^contentHeightDidChange)(void);
@property(nonatomic, assign) BOOL showsCategorySectionEnabled;
@property(nonatomic, assign) BOOL showsTagSectionEnabled;
@property(nonatomic, assign) BOOL showsAppSectionEnabled;
@property(nonatomic, assign) BOOL keepsSelectedSectionsVisible;

- (void)updateWithSearchCriteria:(MTSearchCriteria *)searchCriteria
                       tagTokens:(NSArray<MTSearchToken *> *)tagTokens
                       appTokens:(NSArray<MTSearchToken *> *)appTokens;
- (void)resetSearchSessionState;
- (CGFloat)preferredContentHeightForWidth:(CGFloat)width;

@end

NS_ASSUME_NONNULL_END
