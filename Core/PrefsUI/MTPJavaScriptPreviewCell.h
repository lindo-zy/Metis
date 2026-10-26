#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 两种脚本入口共用预览布局，校验与容量遵循各自的 runtime profile。
@interface MTPJavaScriptPreviewCell : UITableViewCell
- (instancetype)initWithSource:(NSString *)source usage:(NSString *)usage invalid:(BOOL)invalid;
+ (void)alignScriptRow:(UITableViewCell *)cell;
@end

NS_ASSUME_NONNULL_END
