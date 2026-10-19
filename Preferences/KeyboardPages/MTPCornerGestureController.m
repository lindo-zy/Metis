#import "MTPanelRegistry.h"
#import "MTPCornerGestureController.h"
#import "MTPLinkActionEditorController.h"
#import "MTPGestureActionCell.h"
#import "MTCornerGesturePolicy.h"
#import "MTGlobalPanelPolicy.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTCornerLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSDictionary *MTCornerDefinition(NSDictionary *preferences, NSString *selector) {
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static NSString *MTCornerActionName(NSDictionary *preferences, NSString *slot) {
    NSString *selector = MTCornerGestureConfiguredSelector(preferences, slot);
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if ([panel[@"kind"] isEqual:MTPanelGestureKind]) return MTPanelString(panel[@"name"]);
    NSDictionary *entry = MTCornerDefinition(preferences, selector);
    if (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry)) return MTCornerLocalized(@"CORNER_UNASSIGNED");
    NSString *name = MTGlobalPanelString(entry[@"name"]);
    return name.length ? name : MTCornerLocalized(@"DEFAULT_BUTTON_NAME");
}
static BOOL MTCornerSaveSelector(NSString *slot, NSString *selector) {
    if (!MTCornerGestureSlotValid(slot)) {
        NSLog(@"[MetisKeyboard][CornerSettings] save rejected: invalid slot");
        return NO;
    }
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    id stored = preferences[kMTCornerGestureBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [bindings[slot] isKindOfClass:NSDictionary.class]
        ? [bindings[slot] mutableCopy] : [NSMutableDictionary dictionary];
    if ([selector isKindOfClass:NSString.class] && selector.length) {
        entry[@"selector"] = selector;
        entry[@"enabled"] = @YES;
    } else {
        [entry removeObjectForKey:@"selector"];
    }
    bindings[slot] = entry;
    preferences[kMTCornerGestureBindings] = bindings;
    [manager writePrefs:preferences];
    NSString *saved = MTCornerGestureConfiguredSelector([manager readPrefs], slot);
    BOOL success = selector.length ? [saved isEqual:selector] : saved == nil;
    NSLog(@"[MetisKeyboard][CornerSettings] save slot=%@ cleared=%d success=%d", slot, ![selector length], success);
    return success;
}

// 顶部示意图：按当前半径/张角把两角扇形用颜色实时标出（已绑定的角落高亮，
// 未绑定的角落淡显），滑杆拖动即刷新——调节时直接看到生效范围。
@interface MTPCornerPreviewView : UIView
@property(nonatomic) double radius;
@property(nonatomic) double angle;
@property(nonatomic) BOOL leftAssigned;
@property(nonatomic) BOOL rightAssigned;
@end
@implementation MTPCornerPreviewView
- (void)setRadius:(double)radius { _radius = radius; [self setNeedsDisplay]; }
- (void)setAngle:(double)angle { _angle = angle; [self setNeedsDisplay]; }
- (void)setLeftAssigned:(BOOL)leftAssigned { _leftAssigned = leftAssigned; [self setNeedsDisplay]; }
- (void)setRightAssigned:(BOOL)rightAssigned { _rightAssigned = rightAssigned; [self setNeedsDisplay]; }
- (void)drawFanAtCorner:(CGPoint)anchor radius:(CGFloat)radius halfAngle:(double)half
    bisector:(double)bisector color:(UIColor *)color assigned:(BOOL)assigned {
    UIBezierPath *fan = [UIBezierPath bezierPath];
    [fan moveToPoint:anchor];
    [fan addArcWithCenter:anchor radius:radius startAngle:bisector - half endAngle:bisector + half clockwise:YES];
    [fan closePath];
    UIColor *fill = [color colorWithAlphaComponent:assigned ? 0.45 : 0.15];
    [fill setFill];
    [fan fill];
    color = [color colorWithAlphaComponent:assigned ? 0.9 : 0.35];
    [color setStroke];
    fan.lineWidth = 1.5;
    [fan stroke];
}
- (void)drawRect:(__unused CGRect)rect {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat margin = 14;
    CGFloat scale = MIN((self.bounds.size.width - margin * 2) / screen.width, (self.bounds.size.height - margin * 2) / screen.height);
    if (scale <= 0 || !isfinite(scale)) return;
    CGFloat width = screen.width * scale, height = screen.height * scale;
    CGRect device = CGRectMake((self.bounds.size.width - width) / 2, (self.bounds.size.height - height) / 2, width, height);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:device cornerRadius:width * 0.12];
    [UIColor.secondarySystemBackgroundColor setFill];
    [body fill];
    [UIColor.separatorColor setStroke];
    body.lineWidth = 1;
    [body stroke];
    CGFloat radius = MAX(4, self.radius * scale);
    double half = self.angle * M_PI / 180 / 2;
    [self drawFanAtCorner:CGPointMake(CGRectGetMinX(device), CGRectGetMaxY(device)) radius:radius halfAngle:half
        bisector:-M_PI / 4 color:UIColor.systemBlueColor assigned:self.leftAssigned];
    [self drawFanAtCorner:CGPointMake(CGRectGetMaxX(device), CGRectGetMaxY(device)) radius:radius halfAngle:half
        bisector:-M_PI * 3 / 4 color:UIColor.systemOrangeColor assigned:self.rightAssigned];
}
@end

@interface MTPCornerActionPicker : PSListController
@property(nonatomic) BOOL selectAfterSave;
@end

@interface MTPCornerGestureController ()
@property(nonatomic, strong) MTPCornerPreviewView *previewView;
// 滑杆落盘去抖：拖动期间只更新示意图，停止拖动后才写偏好，避免连续写盘
// 持续广播 prefschanged（宿主会 reload 并全量重扫窗口）。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *pendingSliderValues;
@property(nonatomic) NSUInteger sliderCommitGeneration;
@end

@implementation MTPCornerGestureController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTCornerLocalized(@"CORNER_GESTURE_SETTINGS");
    MTPCornerPreviewView *preview = [[MTPCornerPreviewView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 190)];
    preview.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    preview.backgroundColor = UIColor.clearColor;
    // PSListController 在 iOS 16 上提供 table，不保证实现头文件声明的 tableView。
    [self table].tableHeaderView = preview;
    self.previewView = preview;
    [self refreshPreview];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
    [self refreshPreview];
}
- (void)refreshPreview {
    if (!self.previewView) return;
    NSMutableDictionary *preferences = [[MTPrefsManager.sharedInstance readPrefs] mutableCopy];
    [preferences addEntriesFromDictionary:self.pendingSliderValues ?: @{}];
    self.previewView.radius = MTCornerGestureRadius(preferences);
    self.previewView.angle = MTCornerGestureAngle(preferences);
    BOOL enabled = MTCornerGestureMasterEnabled(preferences);
    self.previewView.leftAssigned = enabled && [self assigned:@[@"bottomleft"] inPreferences:preferences];
    self.previewView.rightAssigned = enabled && [self assigned:@[@"bottomright"] inPreferences:preferences];
}
- (BOOL)assigned:(NSArray<NSString *> *)regions inPreferences:(NSDictionary *)preferences {
    for (NSString *region in regions)
        if (MTCornerGestureSelector(preferences, MTCornerGestureSlot(region))) return YES;
    return NO;
}
- (PSSpecifier *)toggle {
    return [PSSpecifier preferenceSpecifierNamed:MTCornerLocalized(@"ENABLED") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
}
- (PSSpecifier *)slider:(NSString *)title key:(NSString *)key min:(double)min max:(double)max fallback:(double)fallback {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTCornerLocalized(title) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSliderCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@(min) forKey:@"min"];
    [item setProperty:@(max) forKey:@"max"];
    [item setProperty:@(fallback) forKey:@"default"];
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTCornerLocalized(@"CORNER_GESTURE_SETTINGS")];
    [group setProperty:MTCornerLocalized(@"CORNER_GESTURE_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *master = [self toggle];
    [master setProperty:kMTCornerGesturesEnabled forKey:@"key"];
    [master setProperty:@YES forKey:@"default"];
    [items addObject:master];
    [items addObject:[self slider:@"CORNER_RADIUS" key:kMTCornerGestureRadiusKey
        min:kMTCornerGestureRadiusMin max:kMTCornerGestureRadiusMax fallback:kMTCornerGestureRadiusDefault]];
    [items addObject:[self slider:@"CORNER_ANGLE" key:kMTCornerGestureAngleKey
        min:kMTCornerGestureAngleMin max:kMTCornerGestureAngleMax fallback:kMTCornerGestureAngleDefault]];
    for (NSString *region in MTCornerGestureRegions()) {
        NSString *slot = MTCornerGestureSlot(region);
        [items addObject:[PSSpecifier groupSpecifierWithName:MTCornerLocalized(
            [region isEqual:@"bottomleft"] ? @"CORNER_BOTTOMLEFT" : @"CORNER_BOTTOMRIGHT")]];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MTCornerLocalized(@"CORNER_ENABLE") target:self
            set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:slot forKey:@"cornerSlot"];
        [enabled setProperty:@YES forKey:@"default"];
        [items addObject:enabled];
        PSSpecifier *action = [PSSpecifier preferenceSpecifierNamed:MTCornerLocalized(@"CORNER_ACTION") target:self set:nil get:@selector(readActionName:)
            detail:MTPCornerActionPicker.class cell:PSLinkCell edit:nil];
        action.identifier = [@"corner-action-" stringByAppendingString:region];
        [action setProperty:slot forKey:@"cornerSlot"];
        [items addObject:action];
    }
    _specifiers = items;
    return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        id value = self.pendingSliderValues[key] ?: preferences[key];
        if ([key isEqual:kMTCornerGestureRadiusKey]) return @(MTCornerGestureRadius(@{key: value ?: @0}));
        if ([key isEqual:kMTCornerGestureAngleKey]) return @(MTCornerGestureAngle(@{key: value ?: @0}));
        return [value isKindOfClass:NSNumber.class] ? value : [specifier propertyForKey:@"default"];
    }
    NSString *slot = [specifier propertyForKey:@"cornerSlot"];
    if (slot) {
        id enabled = MTCornerGestureBinding(preferences, slot)[@"enabled"];
        return @([enabled isKindOfClass:NSNumber.class] ? [enabled boolValue] : YES);
    }
    return nil;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqual:kMTCornerGesturesEnabled]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        [[MTPrefsManager sharedInstance] setValue:@([value boolValue]) forKey:key];
        [self refreshPreview];
        return;
    }
    if ([key isEqual:kMTCornerGestureRadiusKey] || [key isEqual:kMTCornerGestureAngleKey]) {
        double clamped = MTCornerGestureClamp([value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN,
            [specifier propertyForKey:@"min"] ? [(NSNumber *)[specifier propertyForKey:@"min"] doubleValue] : -INFINITY,
            [specifier propertyForKey:@"max"] ? [(NSNumber *)[specifier propertyForKey:@"max"] doubleValue] : INFINITY,
            [(NSNumber *)[specifier propertyForKey:@"default"] doubleValue]);
        // 示意图直接用拖动值刷新（不等落盘），落盘延后到停止拖动后。
        if ([key isEqual:kMTCornerGestureRadiusKey]) self.previewView.radius = clamped;
        else if ([key isEqual:kMTCornerGestureAngleKey]) self.previewView.angle = clamped;
        [self scheduleSliderCommitForKey:key value:@(clamped)];
        return;
    }
    NSString *slot = [specifier propertyForKey:@"cornerSlot"];
    if (MTCornerGestureSlotValid(slot) && [value isKindOfClass:NSNumber.class]) {
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences) return;
        id stored = preferences[kMTCornerGestureBindings];
        NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
        NSMutableDictionary *entry = [bindings[slot] isKindOfClass:NSDictionary.class]
            ? [bindings[slot] mutableCopy] : [NSMutableDictionary dictionary];
        entry[@"enabled"] = @([value boolValue]);
        bindings[slot] = entry;
        preferences[kMTCornerGestureBindings] = bindings;
        [manager writePrefs:preferences];
        [self refreshPreview];
    }
}
// 停止拖动 0.4s 后落盘一次；期间的新值覆盖旧值，只保留最后一次。
- (void)scheduleSliderCommitForKey:(NSString *)key value:(NSNumber *)value {
    if (![key length]) return;
    if (!self.pendingSliderValues) self.pendingSliderValues = [NSMutableDictionary dictionary];
    self.pendingSliderValues[key] = value;
    NSUInteger generation = ++self.sliderCommitGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MTPCornerGestureController *controller = weakSelf;
        if (!controller || controller.sliderCommitGeneration != generation) return;
        [controller flushPendingSliderValues];
    });
}
// 页面离开前补写未落盘的滑杆值（含 push 到动作选择页），避免拖动结果丢失。
- (void)flushPendingSliderValues {
    self.sliderCommitGeneration++;
    NSDictionary<NSString *, NSNumber *> *pending = [self.pendingSliderValues copy];
    if (!pending.count) return;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return;
    [preferences addEntriesFromDictionary:pending];
    [manager writePrefs:preferences];
    [self.pendingSliderValues removeAllObjects];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self flushPendingSliderValues];
}
- (id)readActionName:(PSSpecifier *)specifier {
    return MTCornerActionName([MTPrefsManager.sharedInstance readPrefs], [specifier propertyForKey:@"cornerSlot"]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item.cellType == PSLinkCell && [item propertyForKey:@"cornerSlot"])
        return MTPGestureActionCell(tableView, @"MTPCornerActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
@end

@implementation MTPCornerActionPicker
- (NSString *)slot { return [self.specifier propertyForKey:@"cornerSlot"]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTCornerLocalized(@"CHOOSE_ACTION"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.selectAfterSave) { self.selectAfterSave = NO; [self.navigationController popViewControllerAnimated:YES]; }
}
- (PSSpecifier *)action:(NSString *)name selector:(NSString *)selector {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [item setProperty:selector ?: @"" forKey:@"actionSelector"];
    item->action = @selector(selectAction:);
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [items addObject:[self action:MTCornerLocalized(@"CORNER_ACTION_NONE") selector:nil]];
    [items addObject:[PSSpecifier groupSpecifierWithName:MTCornerLocalized(@"PANEL_KIND_GESTURE")]];
    for (NSDictionary *panel in MTPanelDefinitions([MTPrefsManager.sharedInstance readPrefs], MTPanelGestureKind))
        [items addObject:[self action:MTPanelString(panel[@"name"]) selector:MTPanelSelector(panel[@"id"])]];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTCornerLocalized(@"CUSTOM_ACTIONS")];
    [group setProperty:MTCornerLocalized(@"DOCK_ACTION_PICKER_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    id definitions = [[MTPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[]) {
        if (!MTGlobalCustomActionSupported(entry) || !MTIsLinkActionSelector(entry[@"selector"])) continue;
        NSString *name = MTGlobalPanelString(entry[@"name"]);
        PSSpecifier *item = [self action:name.length ? name : MTCornerLocalized(@"DEFAULT_BUTTON_NAME") selector:entry[@"selector"]];
        [item setProperty:[MTHelper imageForIconConfig:entry[@"icon"] defaultSymbolName:@"link"] forKey:@"iconImage"];
        [items addObject:item];
    }
    PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:MTCornerLocalized(@"ADD") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    add->action = @selector(addAction:);
    [items addObject:add];
    _specifiers = items;
    return items;
}
- (void)selectAction:(PSSpecifier *)specifier {
    NSString *selector = [specifier propertyForKey:@"actionSelector"];
    if (![selector isKindOfClass:NSString.class]) return;
    if (selector.length) {
        NSDictionary *entry = MTCornerDefinition([[MTPrefsManager sharedInstance] readPrefs], selector);
        if (!MTPanelAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelGestureKind) &&
            (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry))) { [self reloadSpecifiers]; return; }
    }
    if (MTCornerSaveSelector(self.slot, selector.length ? selector : nil)) [self.navigationController popViewControllerAnimated:YES];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        NSString *chosen = MTCornerGestureConfiguredSelector([MTPrefsManager.sharedInstance readPrefs], self.slot);
        BOOL checked = item->action == @selector(selectAction:) &&
            ([chosen isEqual:[item propertyForKey:@"actionSelector"]] || (!chosen.length && ![[item propertyForKey:@"actionSelector"] length]));
        return MTPGestureActionCell(tableView, @"MTPCornerActionChoice", item.name, nil, [item propertyForKey:@"iconImage"],
            checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone, item);
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (item->action == @selector(selectAction:)) [self selectAction:item]; else [self addAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
- (void)addAction:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTCornerLocalized(@"ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem]) {
        [alert addAction:[UIAlertAction actionWithTitle:[MTPLinkActionEditorController displayNameForType:type] style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) { [weakSelf addType:type]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:MTCornerLocalized(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)addType:(NSString *)type {
    MTPLinkActionEditorController *editor = [MTPLinkActionEditorController new];
    editor.entry = [@{@"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"type": type, @"name": [MTPLinkActionEditorController displayNameForType:type],
        @"icon": [MTPLinkActionEditorController defaultIconForType:type], @"link": @""} mutableCopy];
    __weak typeof(self) weakSelf = self;
    __weak MTPLinkActionEditorController *weakEditor = editor;
    NSString *slot = [self.slot copy];
    __block BOOL completed = NO;
    editor.completion = ^(NSDictionary *entry) {
        MTPCornerActionPicker *picker = weakSelf;
        if (completed || !picker || ![picker.slot isEqual:slot] || ![picker.navigationController.viewControllers containsObject:picker] ||
            picker.navigationController.topViewController != weakEditor || !MTCornerGestureSlotValid(slot)) return;
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences || ![entry isKindOfClass:NSDictionary.class] || !MTIsLinkActionSelector(entry[@"selector"])) return;
        id stored = preferences[kLinkActionskey];
        NSMutableArray *definitions = [stored isKindOfClass:NSArray.class] ? [stored mutableCopy] : [NSMutableArray array];
        [definitions addObject:entry];
        preferences[kLinkActionskey] = definitions;
        completed = YES;
        [manager writePrefs:preferences];
        if (MTGlobalCustomActionSupported(MTCornerDefinition([manager readPrefs], entry[@"selector"])))
            picker.selectAfterSave = MTCornerSaveSelector(slot, entry[@"selector"]);
    };
    [editor setRootController:self.rootController];
    [editor setParentController:self];
    [self pushController:editor];
}
@end
