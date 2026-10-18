#import <UIKit/UIKit.h>
@class PSSpecifier;

// 保留标准 UIKit 标签布局，同时向 QuickPrefs 暴露当前行元数据。
@interface MTPPathTableCell : UITableViewCell
@property (nonatomic, strong) PSSpecifier *specifier;
@end
