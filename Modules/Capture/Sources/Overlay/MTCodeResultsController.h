#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface MTCodeResultsController : UITableViewController
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onCopy)(NSString *text);
@property (nonatomic, copy) void (^onOpenURL)(NSURL *url);
- (instancetype)initWithCodes:(NSArray<NSString *> *)codes;
@end
NS_ASSUME_NONNULL_END
