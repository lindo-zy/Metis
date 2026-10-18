#import <UIKit/UIKit.h>
#import "MTEditorOrder.h"

NS_ASSUME_NONNULL_BEGIN

/// 选区与设置预览共用的工具栏；外观在创建时取快照，调用方负责按钮动作。
/// 排布枚举见 MTEditorOrder.h 的 MTSelectionToolbarArrangement。
@interface MTSelectionToolbar : UIView
@property (nonatomic, copy, readonly) NSArray<UIButton *> *buttons;
@property (nonatomic, assign, readonly) MTSelectionToolbarArrangement arrangement;
- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(MTSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize
                        arrangement:(MTSelectionToolbarArrangement)arrangement;
- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(MTSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize;
- (CGFloat)preferredWidthForAvailableWidth:(CGFloat)availableWidth;
// 多排：每行最多 8 个按钮，窄屏按按钮大小减少列数；高度必须按最终工具栏宽度计算。
// 滑动：只排一行并保持按钮最小宽度，超出的部分横向滑动，高度恒为一排。
- (CGFloat)preferredHeightForAvailableWidth:(CGFloat)availableWidth;
@end

NS_ASSUME_NONNULL_END
