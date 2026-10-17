#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// 与 UIKit 无关：紧凑多排网格，统一供操作、工具和贴纸使用。
typedef struct {
    NSUInteger columns;
    NSUInteger rows;
    CGFloat buttonWidth;
    CGFloat height;
    CGFloat buttonHeight;
    CGFloat gap;
    CGFloat originX;
} MTEditorGridLayout;

MTEditorGridLayout MTEditorGridMake(CGFloat width, NSUInteger count, NSUInteger maximumColumns);
// 17pt 图标对应 scale=1；按钮宽高和间距同比缩放，整组在可用宽度内居中。
MTEditorGridLayout MTEditorGridMakeScaled(CGFloat width, NSUInteger count, NSUInteger maximumColumns, CGFloat scale);
CGRect MTEditorGridFrame(MTEditorGridLayout layout, NSUInteger index);

// 全屏标记：首尾排避开四角，中间排使用两侧空位，最多 8 列。
// grid 保留原窄网格的按钮尺寸和 originX，供四角键沿用原定位。
typedef struct {
    MTEditorGridLayout grid;
    NSUInteger itemCount;
    NSUInteger edgeColumns;
    NSUInteger middleColumns;
    CGFloat panelWidth;
    CGFloat middleButtonWidth;
    CGFloat rowStride;
} MTEditorMarkupGridLayout;

MTEditorMarkupGridLayout MTEditorMarkupGridMakeScaled(CGFloat width, NSUInteger count,
                                                     CGFloat sideMargin, CGFloat scale);
CGRect MTEditorMarkupGridFrame(MTEditorMarkupGridLayout layout, NSUInteger index);

// 实际面板与设置预览共用的内边距、把手高度和四角定位。
FOUNDATION_EXPORT const CGFloat MTEditorPanelPadTop;
FOUNDATION_EXPORT const CGFloat MTEditorPanelPadBottom;
FOUNDATION_EXPORT const CGFloat MTEditorPanelSideMargin;
FOUNDATION_EXPORT const CGFloat MTEditorPanelGripHeight;
FOUNDATION_EXPORT const CGFloat MTEditorRowSliderHeight;
FOUNDATION_EXPORT const CGFloat MTEditorPanelRowGap;

typedef struct {
    CGRect close;
    CGRect color;
    CGRect undo;
    CGRect done;
} MTEditorMarkupCornerFrames;

MTEditorMarkupCornerFrames MTEditorMarkupCornerFramesMake(MTEditorGridLayout layout,
                                                          CGFloat panelWidth, CGFloat gridY,
                                                          CGFloat visibleHeight);

// 全屏标记在独立线宽条和浮动面板之外显示完整图片。
CGRect MTEditorMarkupImageViewport(CGSize size, CGRect panel,
                                   CGFloat safeTop, CGFloat safeLeft,
                                   CGFloat safeBottom, CGFloat safeRight,
                                   CGFloat sliderSpace, BOOL panelAtTop);

// 将浮动面板（或折叠把手）完整限制在可用矩形内。
CGPoint MTEditorClampFloatingOrigin(CGPoint origin, CGSize floatingSize, CGRect allowedBounds);
