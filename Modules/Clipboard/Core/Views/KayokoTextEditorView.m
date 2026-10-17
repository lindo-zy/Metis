//
//  KayokoTextEditorView.m
//  Kayoko
//

#import "KayokoTextEditorView.h"

#import "KayokoHeaderView.h"
#import "KayokoMainView.h"

@interface KayokoTextEditorView () <UITextViewDelegate>

@property(nonatomic, strong, readwrite) KayokoHeaderView *headerView;
@property(nonatomic, strong, readwrite) UITextView *textView;

@end

@implementation KayokoTextEditorView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setClipsToBounds:YES];
        [self setBackgroundColor:[UIColor clearColor]];

        [self setHeaderView:[[KayokoHeaderView alloc] initWithTitle:@""]];
        [self addSubview:[self headerView]];
        [[self headerView] setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[ [[[self headerView] heightAnchor]
                                                    constraintEqualToConstant:[KayokoHeaderView preferredHeight]] ]];

        UITextView *textView = [[UITextView alloc] init];
        [textView setBackgroundColor:[UIColor clearColor]];
        [textView setFont:[UIFont systemFontOfSize:16]];
        [textView setEditable:YES];
        [textView setSelectable:YES];
        [textView setAutomaticallyAdjustsScrollIndicatorInsets:NO];
        [textView setContentInsetAdjustmentBehavior:UIScrollViewContentInsetAdjustmentNever];
        [textView setTextColor:[UIColor labelColor]];
        [textView setDelegate:self];
        [textView setTextContainerInset:UIEdgeInsetsMake(8, 16, 8, 16)];
        [[textView textContainer] setLineFragmentPadding:0];
        [textView setKeyboardDismissMode:UIScrollViewKeyboardDismissModeNone];
        [self setTextView:textView];
        [self addSubview:textView];

        [textView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[textView topAnchor] constraintEqualToAnchor:[[self headerView] bottomAnchor]
                                                 constant:kKayokoHeaderContentSpacing],
            [[textView leadingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] leadingAnchor]],
            [[textView trailingAnchor] constraintEqualToAnchor:[[self safeAreaLayoutGuide] trailingAnchor]],
            [[textView bottomAnchor] constraintEqualToAnchor:[self bottomAnchor]]
        ]];
    }
    return self;
}

- (void)setKeyboardBottomInset:(CGFloat)keyboardBottomInset {
    keyboardBottomInset = MAX(keyboardBottomInset, 0);
    if (_keyboardBottomInset == keyboardBottomInset) {
        return;
    }

    _keyboardBottomInset = keyboardBottomInset;
    [self updateTextViewScrollInsets];
}

- (CGFloat)safeAreaBottomInsetForScrollContent {
    UIView *view = self;
    while (view) {
        if ([view isKindOfClass:[KayokoMainView class]]) {
            return [(KayokoMainView *)view safeAreaBottomInsetForContentView:self];
        }
        view = [view superview];
    }

    return MAX([self safeAreaInsets].bottom, 0);
}

- (CGFloat)scrollBottomInset {
    if ([self keyboardBottomInset] > 0) {
        return [self keyboardBottomInset];
    }
    return [self safeAreaBottomInsetForScrollContent];
}

- (void)updateTextViewScrollInsets {
    CGFloat bottomInset = [self scrollBottomInset];
    UIEdgeInsets contentInset = [[self textView] contentInset];
    contentInset.bottom = bottomInset;
    [[self textView] setContentInset:contentInset];
    [[self textView] setVerticalScrollIndicatorInsets:UIEdgeInsetsMake(0, 0, bottomInset, 0)];
}

- (void)setEditorText:(NSString *)text {
    [[self textView] setText:text ?: @""];
    [[self textView] setSelectedRange:NSMakeRange([[self textView] text].length, 0)];
    [self updateTextViewScrollInsets];
}

- (NSString *)editorText {
    return [[self textView] text] ?: @"";
}

- (void)reset {
    [[self textView] setText:@""];
    [[self textView] setSelectedRange:NSMakeRange(0, 0)];
    [self setKeyboardBottomInset:0];
}

@end
