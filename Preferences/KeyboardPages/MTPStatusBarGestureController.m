#import "MTPanelRegistry.h"
#import "MTPStatusBarGestureController.h"
#import "MTPLinkActionEditorController.h"
#import "MTPGestureActionCell.h"
#import "MTStatusBarGesturePolicy.h"
#import "MTGlobalPanelPolicy.h"
#import "MTHelper.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTStatusLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSString *MTStatusTitle(NSString *kind) {
    return MTStatusLocalized([@"STATUS_BAR_" stringByAppendingString:kind.uppercaseString]);
}
static NSDictionary *MTStatusDefinition(NSDictionary *preferences, NSString *selector) {
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static NSString *MTStatusActionName(NSDictionary *preferences, NSString *slot) {
    NSString *selector = MTGlobalPanelString(MTStatusBarBinding(preferences, slot)[@"selector"]);
    NSDictionary *panel = MTPanelDefinition(preferences, selector);
    if ([panel[@"kind"] isEqual:MTPanelGestureKind]) return MTPanelString(panel[@"name"]);
    NSDictionary *entry = MTStatusDefinition(preferences, selector);
    if (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry)) return MTStatusLocalized(@"STATUS_BAR_UNASSIGNED");
    NSString *name = MTGlobalPanelString(entry[@"name"]);
    return name.length ? name : MTStatusLocalized(@"DEFAULT_BUTTON_NAME");
}
static BOOL MTStatusSlotValid(NSString *slot) {
    if (![slot isKindOfClass:NSString.class]) return NO;
    NSArray *parts = [slot componentsSeparatedByString:@"."];
    return parts.count == 2 && [MTStatusBarSlot(parts[0], parts[1]) isEqual:slot];
}
static BOOL MTStatusSaveBinding(NSString *slot, NSString *field, id value) {
    if (!MTStatusSlotValid(slot) || !field.length) {
        NSLog(@"[MetisKeyboard][StatusBarSettings] save rejected: invalid slot or field");
        return NO;
    }
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    id stored = preferences[kMTStatusBarBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [MTStatusBarBinding(preferences, slot) mutableCopy];
    if (value) entry[field] = value; else [entry removeObjectForKey:field];
    bindings[slot] = entry;
    preferences[kMTStatusBarBindings] = bindings;
    [manager writePrefs:preferences];
    id saved = MTStatusBarBinding([manager readPrefs], slot)[field];
    BOOL success = value ? [saved isEqual:value] : saved == nil;
    NSLog(@"[MetisKeyboard][StatusBarSettings] save slot=%@ field=%@ success=%d", slot, field, success);
    return success;
}

@interface MTPStatusBarActionPicker : PSListController
@property(nonatomic) BOOL selectAfterSave;
@end
@interface MTPStatusBarGestureEntryController : PSListController
@end

@implementation MTPStatusBarGestureController
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTStatusLocalized(@"STATUS_BAR_SETTINGS"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (PSSpecifier *)toggle:(NSString *)title key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTStatusLocalized(title) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@NO forKey:@"default"];
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTStatusLocalized(@"STATUS_BAR_SETTINGS")];
    [group setProperty:MTStatusLocalized(@"STATUS_BAR_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self toggle:@"ENABLED" key:kMTStatusBarEnabled]];
    [items addObject:[self toggle:@"STATUS_BAR_LANDSCAPE" key:kMTStatusBarLandscape]];
    for (NSString *region in MTStatusBarRegions()) {
        [items addObject:[PSSpecifier groupSpecifierWithName:MTStatusTitle(region)]];
        for (NSString *gesture in MTStatusBarGestures()) {
            PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTStatusTitle(gesture) target:self set:nil get:nil
                detail:MTPStatusBarGestureEntryController.class cell:PSLinkCell edit:nil];
            item.identifier = MTStatusBarSlot(region, gesture);
            [item setProperty:MTStatusBarSlot(region, gesture) forKey:@"statusBarSlot"];
            [item setProperty:[NSString stringWithFormat:@"%@ · %@", MTStatusTitle(region), MTStatusTitle(gesture)] forKey:@"entryTitle"];
            [items addObject:item];
        }
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTStatusBarFlag([[MTPrefsManager sharedInstance] readPrefs][[specifier propertyForKey:@"key"]]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) [[MTPrefsManager sharedInstance] setValue:@(MTStatusBarFlag(value)) forKey:key];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    NSString *slot = [item propertyForKey:@"statusBarSlot"];
    if (item.cellType == PSLinkCell && slot.length)
        return MTPGestureActionCell(tableView, @"MTPStatusGestureRecord", item.name,
            MTStatusActionName([MTPrefsManager.sharedInstance readPrefs], slot), nil, UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
@end

@implementation MTPStatusBarGestureEntryController
- (void)viewDidLoad { [super viewDidLoad]; self.title = [self.specifier propertyForKey:@"entryTitle"]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSString *slot = [self.specifier propertyForKey:@"statusBarSlot"];
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTStatusLocalized(@"STATUS_BAR_ENTRY_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MTStatusLocalized(@"ENABLED") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:slot forKey:@"statusBarSlot"];
    [items addObject:enabled];
    PSSpecifier *action = [PSSpecifier preferenceSpecifierNamed:MTStatusLocalized(@"CHOOSE_ACTION") target:self set:nil get:@selector(readActionName:)
        detail:MTPStatusBarActionPicker.class cell:PSLinkCell edit:nil];
    action.identifier = @"choose-action";
    [action setProperty:slot forKey:@"statusBarSlot"];
    [items addObject:action];
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:MTStatusLocalized(@"STATUS_BAR_CLEAR") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear->action = @selector(clearAction:);
    [items addObject:clear];
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTStatusBarFlag(MTStatusBarBinding([[MTPrefsManager sharedInstance] readPrefs], [specifier propertyForKey:@"statusBarSlot"])[@"enabled"]));
}
- (id)readActionName:(PSSpecifier *)specifier {
    return MTStatusActionName([MTPrefsManager.sharedInstance readPrefs], [specifier propertyForKey:@"statusBarSlot"]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item.cellType == PSLinkCell)
        return MTPGestureActionCell(tableView, @"MTPStatusActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    MTStatusSaveBinding([specifier propertyForKey:@"statusBarSlot"], @"enabled", @(MTStatusBarFlag(value)));
}
- (void)clearAction:(PSSpecifier *)specifier {
    (void)specifier;
    MTStatusSaveBinding([self.specifier propertyForKey:@"statusBarSlot"], @"selector", nil);
    [self reloadSpecifiers];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    if (item && item->action == @selector(clearAction:)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self clearAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
@end

@implementation MTPStatusBarActionPicker
- (NSString *)slot { return [self.specifier propertyForKey:@"statusBarSlot"]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTStatusLocalized(@"CHOOSE_ACTION"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.selectAfterSave) { self.selectAfterSave = NO; [self.navigationController popViewControllerAnimated:YES]; }
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:MTStatusLocalized(@"PANEL_KIND_GESTURE")]];
    for (NSDictionary *panel in MTPanelDefinitions([MTPrefsManager.sharedInstance readPrefs], MTPanelGestureKind)) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTPanelString(panel[@"name"])
            target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [item setProperty:MTPanelSelector(panel[@"id"]) forKey:@"actionSelector"];
        item->action = @selector(selectAction:); [items addObject:item];
    }
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTStatusLocalized(@"CUSTOM_ACTIONS")];
    [group setProperty:MTStatusLocalized(@"STATUS_BAR_PICKER_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    id definitions = [[MTPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[]) {
        if (!MTGlobalCustomActionSupported(entry) || !MTIsLinkActionSelector(entry[@"selector"])) continue;
        NSString *name = MTGlobalPanelString(entry[@"name"]);
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name.length ? name : MTStatusLocalized(@"DEFAULT_BUTTON_NAME")
            target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [item setProperty:entry[@"selector"] forKey:@"actionSelector"];
        [item setProperty:[MTHelper imageForIconConfig:entry[@"icon"] defaultSymbolName:@"link"] forKey:@"iconImage"];
        item->action = @selector(selectAction:); [items addObject:item];
    }
    PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:MTStatusLocalized(@"ADD") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    add->action = @selector(addAction:); [items addObject:add];
    _specifiers = items; return items;
}
- (void)selectAction:(PSSpecifier *)specifier {
    NSString *selector = [specifier propertyForKey:@"actionSelector"];
    if (![selector isKindOfClass:NSString.class] || !selector.length) return;
    NSDictionary *entry = MTStatusDefinition([[MTPrefsManager sharedInstance] readPrefs], selector);
    if (!MTPanelAllowed([MTPrefsManager.sharedInstance readPrefs], selector, MTPanelGestureKind) && (!MTIsLinkActionSelector(selector) || !MTGlobalCustomActionSupported(entry))) { [self reloadSpecifiers]; return; }
    if (MTStatusSaveBinding(self.slot, @"selector", selector)) [self.navigationController popViewControllerAnimated:YES];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self specifierAtIndexPath:indexPath];
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        NSString *chosen = MTGlobalPanelString(MTStatusBarBinding([MTPrefsManager.sharedInstance readPrefs], self.slot)[@"selector"]);
        BOOL checked = chosen.length && [chosen isEqual:[item propertyForKey:@"actionSelector"]];
        return MTPGestureActionCell(tableView, @"MTPStatusActionChoice", item.name, nil, [item propertyForKey:@"iconImage"],
            checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone, item);
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // The row owns the action payload; pass its specifier explicitly.
    PSSpecifier *item = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (item->action == @selector(selectAction:)) [self selectAction:item];
        else [self addAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
- (void)addAction:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MTStatusLocalized(@"ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem]) {
        [alert addAction:[UIAlertAction actionWithTitle:[MTPLinkActionEditorController displayNameForType:type] style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) { [weakSelf addType:type]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:MTStatusLocalized(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
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
        MTPStatusBarActionPicker *picker = weakSelf;
        if (completed || !picker || !MTStatusSlotValid(slot) || ![picker.slot isEqual:slot] ||
            ![picker.navigationController.viewControllers containsObject:picker] ||
            picker.navigationController.topViewController != weakEditor) return;
        MTPrefsManager *manager = MTPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences || ![entry isKindOfClass:NSDictionary.class] || !MTIsLinkActionSelector(entry[@"selector"])) return;
        id stored = preferences[kLinkActionskey];
        NSMutableArray *definitions = [stored isKindOfClass:NSArray.class] ? [stored mutableCopy] : [NSMutableArray array];
        [definitions addObject:entry]; preferences[kLinkActionskey] = definitions;
        completed = YES;
        [manager writePrefs:preferences];
        if (MTGlobalCustomActionSupported(MTStatusDefinition([manager readPrefs], entry[@"selector"]))) {
            picker.selectAfterSave = MTStatusSaveBinding(slot, @"selector", entry[@"selector"]);
        }
    };
    [editor setRootController:self.rootController]; [editor setParentController:self]; [self pushController:editor];
}
@end
