#import <UIKit/UIKit.h>

// 选区模式、尺寸与完成提示共用紧凑气泡规格；宽度只随文案长度变化。
static const CGFloat MTCaptureBubbleHeight = 28.0;
static const CGFloat MTCaptureBubbleHorizontalPadding = 8.0;
static const CGFloat MTCaptureBubbleCornerRadius = 9.0;
static inline UIFont *MTCaptureBubbleFont(void) {
    return [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
}
static inline UIColor *MTCaptureBubbleBackgroundColor(void) {
    return [UIColor colorWithWhite:0.0 alpha:0.7];
}
static inline void MTStyleCaptureBubbleLabel(UILabel *label) {
    label.font = MTCaptureBubbleFont();
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = MTCaptureBubbleBackgroundColor();
    label.layer.cornerRadius = MTCaptureBubbleCornerRadius;
    label.clipsToBounds = YES;
}
