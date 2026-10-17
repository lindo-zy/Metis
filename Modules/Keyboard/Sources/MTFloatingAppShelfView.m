#import "MTFloatingAppShelfView.h"
#import "MTFloatingAppShelfChannel.h"
#import "MTSystemOpenBroker.h"
#import "MTHelper.h"
#import "common.h"
#import "MTShared.h"
#import <notify.h>

@interface MTFloatingAppShelfView ()
@property(nonatomic, strong) UILabel *message;
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, copy) NSString *pendingIdentifier;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic) NSUInteger messageGeneration;
@property(nonatomic) int token;
@end
@implementation MTFloatingAppShelfView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.token = NOTIFY_TOKEN_INVALID;
        self.clipsToBounds = YES;
        self.message = [UILabel new];
        self.message.hidden = YES;
        self.message.numberOfLines = 2;
        self.message.textAlignment = NSTextAlignmentCenter;
        self.message.font = [UIFont systemFontOfSize:11];
        self.message.textColor = UIColor.labelColor;
        self.message.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.message.userInteractionEnabled = NO;
        [self addSubview:self.message];
        __weak typeof(self) weakSelf = self;
        int token = NOTIFY_TOKEN_INVALID;
        if (notify_register_dispatch(MTFloatingShelfChangedName, &token, dispatch_get_main_queue(), ^(__unused int changed) {
            [weakSelf refresh];
        }) == NOTIFY_STATUS_OK) self.token = token;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
        [self refresh];
    }
    return self;
}
- (void)dealloc {
    if (self.token != NOTIFY_TOKEN_INVALID) notify_cancel(self.token);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (BOOL)unlocked { return [self.snapshot[@"unlocked"] boolValue]; }
- (void)didMoveToWindow { [super didMoveToWindow]; if (self.window) [self refresh]; }
- (void)refresh {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; }); return; }
    NSDictionary *snapshot = MTReadFloatingShelf();
    if (!snapshot || [snapshot isEqual:self.snapshot]) return;
    self.snapshot = snapshot;
    for (UIButton *button in self.buttons) [button removeFromSuperview];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSDictionary *item in snapshot[@"items"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.accessibilityIdentifier = item[@"bundleID"];
        button.accessibilityLabel = item[@"title"];
        BOOL active = [snapshot[@"active"] isEqual:item[@"bundleID"]];
        BOOL foreground = [snapshot[@"foreground"] isEqual:item[@"bundleID"]];
        button.accessibilityValue = active ? LOCALIZED(@"FLOATING_SHELF_ACTIVE") :
            (foreground ? LOCALIZED(@"FLOATING_SHELF_FOREGROUND") : nil);
        button.backgroundColor = active ? [UIColor.systemBlueColor colorWithAlphaComponent:0.12] : UIColor.clearColor;
        button.layer.cornerRadius = 8;
        UIImage *icon = [MTHelper appIconImageForBundleID:item[@"bundleID"]] ?: [UIImage systemImageNamed:@"app"];
        [button setImage:icon forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.tintColor = UIColor.secondaryLabelColor;
        // 快照仅用于展示：前台/悬浮状态可能已过期，不能据此永久禁用恢复入口。
        // SpringBoard 收到点击后实时校验全屏前台，同一悬浮会话则幂等返回成功。
        button.enabled = ![self.pendingIdentifier isEqual:item[@"bundleID"]];
        [button addTarget:self action:@selector(activate:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
    [self bringSubviewToFront:self.message];
    [self setNeedsLayout];
    if (self.contentChanged) self.contentChanged();
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat slotWidth = width / MTFloatingShelfCapacity;
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        self.buttons[index].frame = CGRectMake(index * slotWidth + 3, MTBottomToolbarCellTopInset,
            MAX(0, slotWidth - 6), MAX(0, MIN(33, height - MTBottomToolbarCellTopInset)));
    }
    self.message.frame = CGRectMake(0, MTBottomToolbarCellTopInset, width, MAX(0, height - MTBottomToolbarCellTopInset));
}
- (void)activate:(UIButton *)button {
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    if (!self.window || self.hidden || self.pendingIdentifier ||
        ![preferences[kFloatingShelfEnabledKey] isKindOfClass:NSNumber.class] || ![preferences[kFloatingShelfEnabledKey] boolValue] || ![self.buttons containsObject:button]) return;
    NSString *identifier = [button.accessibilityIdentifier copy];
    uint64_t revision = [self.snapshot[@"revision"] unsignedLongLongValue];
    if ([self.snapshot[@"active"] isEqual:identifier] || [self.snapshot[@"foreground"] isEqual:identifier])
        NSLog(@"[MetisKeyboard][FloatingShelf] restore revalidate bundleID=%@ revision=%llu", identifier, (unsigned long long)revision);
    self.pendingIdentifier = identifier;
    NSUInteger generation = ++self.requestGeneration;
    button.enabled = NO;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.center = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
    [button addSubview:spinner]; [spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    MTRestoreFloatingApplication(identifier, revision, ^(MTSystemOpenResult result) {
        MTFloatingAppShelfView *view = weakSelf;
        if (!view || view.requestGeneration != generation || ![view.pendingIdentifier isEqual:identifier]) return;
        view.pendingIdentifier = nil;
        [spinner removeFromSuperview];
        for (UIButton *current in view.buttons) current.enabled = YES;
        [view refresh];
        if (result != MTSystemOpenSucceeded && view.window && !view.hidden) {
            NSUInteger messageGeneration = ++view.messageGeneration;
            view.message.text = LOCALIZED(@"FLOATING_SHELF_RESTORE_FAILED"); view.message.hidden = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (weakSelf.messageGeneration == messageGeneration) weakSelf.message.hidden = YES;
            });
        }
    });
}
@end
