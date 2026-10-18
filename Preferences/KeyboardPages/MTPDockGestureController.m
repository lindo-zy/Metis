#import "MTPanelRegistry.h"
#import "MTPDockGestureController.h"
#import "MTPLinkActionEditorController.h"
#import "MTPGestureActionCell.h"
#import "MTDockGesturePolicy.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTDockLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static BOOL MTDockSaveSelector(NSString *direction, NSString *selector) {
    if (!MTDockGestureEnabledKey(direction) || ![selector isKindOfClass:NSString.class]) return NO;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    id stored = preferences[kMTDockGestureBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    bindings[direction] = selector;
    preferences[kMTDockGestureBindings] = bindings;
    [manager writePrefs:preferences];
    id saved = [manager readPrefs][kMTDockGestureBindings];
    BOOL success = [saved isKindOfClass:NSDictionary.class] && [saved[direction] isEqual:selector];
    NSLog(@"[MetisKeyboard][DockSettings] save direction=%@ success=%d", direction, success);
    return success;
}

@interface MTPDockActionPicker : PSListController
@property(nonatomic) BOOL selectAfterSave;
@end

@implementation MTPDockGestureController
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTDockLocalized(@"DOCK_GESTURE_SETTINGS"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *direction in MTDockGestureDirections()) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
        if ([direction isEqual:@"up"]) [group setProperty:MTDockLocalized(@"DOCK_GESTURE_FOOTER") forKey:@"footerText"];
        [items addObject:group];
        NSString *suffix = direction.uppercaseString;
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MTDockLocalized([@"DOCK_ENABLE_" stringByAppendingString:suffix]) target:self
            set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:direction forKey:@"dockDirection"];
        [enabled setProperty:@([direction isEqual:@"up"]) forKey:@"default"];
        [items addObject:enabled];
        PSSpecifier *action = [PSSpecifier preferenceSpecifierNamed:MTDockLocalized([@"DOCK_ACTION_" stringByAppendingString:suffix]) target:self
            set:nil get:@selector(readActionName:) detail:MTPDockActionPicker.class cell:PSLinkCell edit:nil];
        action.identifier = [@"dock-action-" stringByAppendingString:direction];
        [action setProperty:direction forKey:@"dockDirection"];
        [items addObject:action];
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTDockGestureEnabled([[MTPrefsManager sharedInstance] readPrefs], [specifier propertyForKey:@"dockDirection"]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = MTDockGestureEnabledKey([specifier propertyForKey:@"dockDirection"]);
    if (key && [value isKindOfClass:NSNumber.class]) [[MTPrefsManager sharedInstance] setValue:@([value boolValue]) forKey:key];
}
- (id)readActionName:(PSSpecifier *)specifier {
    NSDictionary *preferences = [[MTPrefsManager sharedInstance] readPrefs];
    NSString *selector = MTDockGestureConfiguredSelector(preferences, [specifier propertyForKey:@"dockDirection"]);
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if ([panel[@"kind"] isEqual:MTPanelGestureKind]) return MTPanelString(panel[@"name"]);
    NSDictionary *entry = MTDockGestureDefinition(preferences, selector, kLinkActionskey);
    if (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry)) return MTDockLocalized(@"DOCK_ACTION_NONE");
    NSString *name = MTGlobalPanelString(entry[@"name"]);
    return name.length ? name : MTDockLocalized(@"DEFAULT_BUTTON_NAME");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item.cellType == PSLinkCell && [item propertyForKey:@"dockDirection"])
        return MTPGestureActionCell(tableView, @"MTPDockActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
@end

@implementation MTPDockActionPicker
- (NSString *)direction { return [self.specifier propertyForKey:@"dockDirection"]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTDockLocalized(@"CHOOSE_ACTION"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.selectAfterSave) { self.selectAfterSave = NO; [self.navigationController popViewControllerAnimated:YES]; }
}
- (PSSpecifier *)action:(NSString *)name selector:(NSString *)selector {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [item setProperty:selector forKey:@"actionSelector"];
    item->action = @selector(selectAction:);
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [items addObject:[self action:MTDockLocalized(@"DOCK_ACTION_NONE") selector:@""]];
    [items addObject:[PSSpecifier groupSpecifierWithName:MTDockLocalized(@"PANEL_KIND_GESTURE")]];
    for (NSDictionary *panel in MTPanelDefinitions([MTPrefsManager.sharedInstance readPrefs], MTPanelGestureKind))
        [items addObject:[self action:MTPanelString(panel[@"name"]) selector:MTPanelSelector(panel[@"id"])]];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTDockLocalized(@"CUSTOM_ACTIONS")];
    [group setProperty:MTDockLocalized(@"DOCK_ACTION_PICKER_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    id definitions = [[MTPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[]) {
        if (!MTGlobalCustomActionSupported(entry) || !MTIsLinkActionSelector(entry[@"selector"])) continue;
        NSString *name = MTGlobalPanelString(entry[@"name"]);
        PSSpecifier *item = [self action:name.length ? name : MTDockLocalized(@"DEFAULT_BUTTON_NAME") selector:entry[@"selector"]];
        [item setProperty:[MTHelper imageForIconConfig:entry[@"icon"] defaultSymbolName:@"link"] forKey:@"iconImage"];
        [items addObject:item];
    }
    PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:MTDockLocalized(@"ADD") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    add->action = @selector(addAction:); [items addObject:add];
    _specifiers = items; return items;
}
- (void)selectAction:(PSSpecifier *)specifier {
    NSString *selector = [specifier propertyForKey:@"actionSelector"];
    if (![selector isKindOfClass:NSString.class]) return;
    NSDictionary *entry = MTDockGestureDefinition([[MTPrefsManager sharedInstance] readPrefs], selector, kLinkActionskey);
    if (selector.length && !MTPanelAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelGestureKind) && (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry))) {
        [self reloadSpecifiers]; return;
    }
    if (MTDockSaveSelector(self.direction, selector)) [self.navigationController popViewControllerAnimated:YES];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        NSString *chosen = MTGlobalPanelString(MTDockGestureConfiguredSelector([MTPrefsManager.sharedInstance readPrefs], self.direction));
        BOOL checked = [chosen isEqual:[item propertyForKey:@"actionSelector"]];
        return MTPGestureActionCell(tableView, @"MTPDockActionChoice", item.name, nil, [item propertyForKey:@"iconImage"],
            checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone, item);
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (item->action == @selector(selectAction:)) [self selectAction:item]; else [self addAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
- (void)addAction:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTDockLocalized(@"ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem])
        [alert addAction:[UIAlertAction actionWithTitle:[MTPLinkActionEditorController displayNameForType:type] style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) { [weakSelf addType:type]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:MTDockLocalized(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)addType:(NSString *)type {
    MTPLinkActionEditorController *editor = [MTPLinkActionEditorController new];
    editor.entry = [@{@"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"type": type, @"name": [MTPLinkActionEditorController displayNameForType:type],
        @"icon": [MTPLinkActionEditorController defaultIconForType:type], @"link": @""} mutableCopy];
    __weak typeof(self) weakSelf = self;
    __weak MTPLinkActionEditorController *weakEditor = editor;
    NSString *direction = [self.direction copy];
    __block BOOL completed = NO;
    editor.completion = ^(NSDictionary *entry) {
        MTPDockActionPicker *picker = weakSelf;
        if (completed || !picker || ![picker.direction isEqual:direction] || ![picker.navigationController.viewControllers containsObject:picker] ||
            picker.navigationController.topViewController != weakEditor || !MTDockGestureEnabledKey(direction)) return;
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences || ![entry isKindOfClass:NSDictionary.class] || !MTIsLinkActionSelector(entry[@"selector"])) return;
        id stored = preferences[kLinkActionskey];
        NSMutableArray *definitions = [stored isKindOfClass:NSArray.class] ? [stored mutableCopy] : [NSMutableArray array];
        [definitions addObject:entry]; preferences[kLinkActionskey] = definitions;
        completed = YES;
        [manager writePrefs:preferences];
        if (MTGlobalCustomActionSupported(MTDockGestureDefinition([manager readPrefs], entry[@"selector"], kLinkActionskey)))
            picker.selectAfterSave = MTDockSaveSelector(direction, entry[@"selector"]);
    };
    [editor setRootController:self.rootController]; [editor setParentController:self]; [self pushController:editor];
}
@end
