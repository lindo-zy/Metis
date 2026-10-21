#import "MTGeometry.h"
#import <math.h>

BOOL MTCaptureStateCanTransition(MTCaptureState from, MTCaptureState to) {
    switch (from) {
        case MTCaptureStateIdle:
            return to == MTCaptureStatePreparing;
        case MTCaptureStatePreparing:
            // 实时区域先显示透明选框，用户选择输出/冻结时才建立快照。
            return to == MTCaptureStateCapturing || to == MTCaptureStatePresenting ||
                   to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStateCapturing:
            return to == MTCaptureStateCaptured || to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStateCaptured:
            return to == MTCaptureStatePresenting || to == MTCaptureStateExporting
                || to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStatePresenting:
            return to == MTCaptureStateEditing || to == MTCaptureStateExporting
                || to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStateEditing:
            return to == MTCaptureStatePresenting || to == MTCaptureStateExporting
                || to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStateExporting:
            return to == MTCaptureStateFinished || to == MTCaptureStatePresenting
                || to == MTCaptureStateCancelling || to == MTCaptureStateFailed;
        case MTCaptureStateCancelling:
            return to == MTCaptureStateCancelled;
        case MTCaptureStateFinished:
        case MTCaptureStateCancelled:
        case MTCaptureStateFailed:
            return NO;
    }
    return NO;
}

BOOL MTCaptureStateIsBusy(MTCaptureState state) {
    switch (state) {
        case MTCaptureStateIdle:
        case MTCaptureStateFinished:
        case MTCaptureStateCancelled:
        case MTCaptureStateFailed:
            return NO;
        default:
            return YES;
    }
}

CGRect MTConvertDisplayRectToPixel(CGRect displayRect, CGSize displayBounds, CGSize pixelSize) {
    if (displayBounds.width <= 0.0 || displayBounds.height <= 0.0
        || pixelSize.width <= 0.0 || pixelSize.height <= 0.0) {
        return CGRectZero;
    }
    CGFloat scaleX = pixelSize.width / displayBounds.width;
    CGFloat scaleY = pixelSize.height / displayBounds.height;

    CGRect result;
    result.origin.x = floor(displayRect.origin.x * scaleX);
    result.origin.y = floor(displayRect.origin.y * scaleY);
    result.size.width = ceil(displayRect.size.width * scaleX);
    result.size.height = ceil(displayRect.size.height * scaleY);

    result = CGRectIntersection(result, CGRectMake(0, 0, pixelSize.width, pixelSize.height));
    if (result.size.width < 1.0 || result.size.height < 1.0) {
        return CGRectZero;
    }
    return result;
}

CGRect MTClampSelectionRect(CGRect rect, CGSize containerSize, CGFloat minimumSize) {
    CGRect container = CGRectMake(0, 0, containerSize.width, containerSize.height);
    rect = CGRectIntersection(rect, container);
    if (CGRectIsNull(rect)) {
        return CGRectZero;
    }

    if (rect.size.width < minimumSize || rect.size.height < minimumSize) {
        // 太小则丢弃，由调用方决定是否重置为默认选区，绝不悄悄产生误触裁剪。
        return CGRectZero;
    }

    CGFloat x = fmin(fmax(rect.origin.x, 0.0), containerSize.width - rect.size.width);
    CGFloat y = fmin(fmax(rect.origin.y, 0.0), containerSize.height - rect.size.height);
    return CGRectMake(x, y, rect.size.width, rect.size.height);
}

CGRect MTConstrainFloatingRect(CGRect frame, CGRect bounds) {
    if (CGRectIsEmpty(frame) || CGRectIsEmpty(bounds) || CGRectIsNull(frame) || CGRectIsNull(bounds) ||
        !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
        !isfinite(frame.size.width) || !isfinite(frame.size.height) ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) return CGRectZero;
    CGFloat otherX = CGRectGetMaxX(bounds) - frame.size.width;
    CGFloat otherY = CGRectGetMaxY(bounds) - frame.size.height;
    frame.origin.x = MAX(MIN(CGRectGetMinX(bounds), otherX), MIN(frame.origin.x, MAX(CGRectGetMinX(bounds), otherX)));
    frame.origin.y = MAX(MIN(CGRectGetMinY(bounds), otherY), MIN(frame.origin.y, MAX(CGRectGetMinY(bounds), otherY)));
    return frame;
}

CGRect MTApplySelectionEdgeSnap(CGRect rect, CGSize containerSize, CGFloat distance) {
    if (!(distance > 0.0) || !isfinite(distance)) return rect;
    if (CGRectIsEmpty(rect) || containerSize.width <= 0.0 || containerSize.height <= 0.0) return rect;
    if (rect.size.width > containerSize.width || rect.size.height > containerSize.height) return rect;
    CGFloat leftGap = rect.origin.x;
    CGFloat rightGap = containerSize.width - CGRectGetMaxX(rect);
    if ((leftGap <= distance || rightGap <= distance) && leftGap <= rightGap) {
        rect.origin.x = 0.0;
    } else if (rightGap <= distance) {
        rect.origin.x = containerSize.width - rect.size.width;
    }
    CGFloat topGap = rect.origin.y;
    CGFloat bottomGap = containerSize.height - CGRectGetMaxY(rect);
    if ((topGap <= distance || bottomGap <= distance) && topGap <= bottomGap) {
        rect.origin.y = 0.0;
    } else if (bottomGap <= distance) {
        rect.origin.y = containerSize.height - rect.size.height;
    }
    return rect;
}

CGRect MTPlaceSelectionToolbar(CGRect preferredFrame, CGRect selectionRect, CGRect availableBounds, CGFloat gap) {
    CGRect bottom = MTConstrainFloatingRect(preferredFrame, availableBounds);
    if (CGRectIsEmpty(bottom) || CGRectIsEmpty(selectionRect) || CGRectIsNull(selectionRect)) return bottom;
    gap = isfinite(gap) ? MAX(0.0, gap) : 0.0;

    // 跟随框选：默认贴在选框下方并按选区水平居中；钳制后仍与选框保持间隙才算放下。
    CGRect below = bottom;
    below.origin.x = CGRectGetMidX(selectionRect) - below.size.width / 2.0;
    below.origin.y = CGRectGetMaxY(selectionRect) + gap;
    below = MTConstrainFloatingRect(below, availableBounds);
    if (CGRectGetMinY(below) >= CGRectGetMaxY(selectionRect) + gap) return below;

    // 选框贴近屏幕底部放不下时改到选框上方。
    CGRect above = bottom;
    above.origin.x = CGRectGetMidX(selectionRect) - above.size.width / 2.0;
    above.origin.y = CGRectGetMinY(selectionRect) - gap - above.size.height;
    above = MTConstrainFloatingRect(above, availableBounds);
    if (CGRectGetMaxY(above) <= CGRectGetMinY(selectionRect) - gap) return above;

    // 接近全屏时可能没有完整空位：保持按钮可达，选重叠较小的一侧。上下都无法
    // 避让（含「全屏」选区这类完全覆盖）时留在底部——平局不再判给顶部，否则面板
    // 会跳到屏幕顶端，远离拇指热区且与默认站位不一致。
    CGRect topOverlap = CGRectIntersection(above, selectionRect);
    CGRect bottomOverlap = CGRectIntersection(below, selectionRect);
    CGFloat topArea = CGRectIsNull(topOverlap) ? 0.0 : topOverlap.size.width * topOverlap.size.height;
    CGFloat bottomArea = CGRectIsNull(bottomOverlap) ? 0.0 : bottomOverlap.size.width * bottomOverlap.size.height;
    return bottomArea <= topArea ? below : above;
}

NSString *MTStringFromCaptureMode(MTCaptureMode mode) {
    switch (mode) {
        case MTCaptureModeFull: return @"full";
        case MTCaptureModeArea: return @"area";
        case MTCaptureModeFreeze: return @"freeze";
        case MTCaptureModeMarkup: return @"markup";
        case MTCaptureModeInstant: return @"instant";
        case MTCaptureModeLong: return @"long";
    }
    return @"unknown";
}

NSString *MTStringFromOutputAction(MTOutputAction action) {
    switch (action) {
        case MTOutputActionSave: return @"save";
        case MTOutputActionCopy: return @"copy";
        case MTOutputActionShare: return @"share";
        case MTOutputActionSaveAndCopy: return @"save+copy";
        case MTOutputActionSaveAndDeleteSource: return @"save+delete-source";
        case MTOutputActionPreviewOnly: return @"preview-only";
    }
    return @"unknown";
}

NSString *MTStringFromCaptureState(MTCaptureState state) {
    switch (state) {
        case MTCaptureStateIdle: return @"idle";
        case MTCaptureStatePreparing: return @"preparing";
        case MTCaptureStateCapturing: return @"capturing";
        case MTCaptureStateCaptured: return @"captured";
        case MTCaptureStatePresenting: return @"presenting";
        case MTCaptureStateEditing: return @"editing";
        case MTCaptureStateExporting: return @"exporting";
        case MTCaptureStateFinished: return @"finished";
        case MTCaptureStateCancelling: return @"cancelling";
        case MTCaptureStateCancelled: return @"cancelled";
        case MTCaptureStateFailed: return @"failed";
    }
    return @"unknown";
}
