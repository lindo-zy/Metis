#import "MTPGestureSettingsController.h"
#import "MTPStatusBarGestureController.h"
#import "MTPDockGestureController.h"
#import "MTKeyboardPanelPreferences.h"
#import "MTHelper.h"
#import "common.h"
#import "MTPSubActionPickerController.h"
#import "MTPPanelActionCatalog.h"
#import "MTPGestureActionCell.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTGestureLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// Both the gesture list and its editor resolve the current saved binding.
static NSString *MTToolbarActionName(PSSpecifier *specifier) {
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    NSString *selector = MTToolbarAction(preferences, [specifier propertyForKey:@"toolbarConfiguration"],
        [specifier propertyForKey:@"toolbarDirection"]);
    NSDictionary *entry = selector.length ? MTPPanelDisplayDefinition(preferences, selector) : nil;
    if (!entry) return MTGestureLocalized(@"STATUS_BAR_UNASSIGNED");
    NSString *name = MTPanelString(entry[@"name"]);
    return name.length ? name : MTGestureLocalized(@"DEFAULT_BUTTON_NAME");
}

// The moved switches retain their original keys and defaults.
@interface MTPPanelGestureController : PSListController
- (PSSpecifier *)toggle:(NSString *)label key:(NSString *)key;
@end
@interface MTPKeyboardGestureController : MTPPanelGestureController
@end

@implementation MTPGestureSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTGestureLocalized(@"GESTURE_SETTINGS");
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *category in @[
        @[@"DOCK_GESTURE_SETTINGS", MTPDockGestureController.class, @"rectangle.bottomthird.inset.filled"],
        @[@"STATUS_BAR_SETTINGS", MTPStatusBarGestureController.class, @"arrow.up.square"],
        @[@"KEYBOARD_GESTURE_SETTINGS", MTPKeyboardGestureController.class, @"keyboard"]
    ]) {
        [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:MTGestureLocalized(category[0]) target:self
            set:nil get:nil detail:category[1] cell:PSLinkCell edit:nil];
        [link setProperty:[MTHelper imageForIconConfig:category[2] defaultSymbolName:@"hand.draw"] forKey:@"iconImage"];
        [items addObject:link];
    }
    _specifiers = items;
    return _specifiers;
}
@end

@implementation MTPPanelGestureController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.specifier.name;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}
- (PSSpecifier *)toggle:(NSString *)label key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTGestureLocalized(label) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@YES forKey:@"default"];
    return item;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [[MTPrefsManager sharedInstance] readPrefs];
    return @(MTKeyboardPanelBool(preferences, [specifier propertyForKey:@"key"], YES));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length && [value isKindOfClass:NSNumber.class])
        [[MTPrefsManager sharedInstance] setValue:@([value boolValue]) forKey:key];
}
@end

@interface MTPToolbarBindingController : PSListController
@end

@implementation MTPKeyboardGestureController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *configuration in @[@"top", @"bottom"]) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:MTGestureLocalized([configuration isEqual:@"top"] ? @"KEYBOARD_PANEL_TOP" : @"KEYBOARD_PANEL_BOTTOM")];
        [group setProperty:MTGestureLocalized(@"PANEL_TOOLBAR_FOOTER") forKey:@"footerText"]; [items addObject:group];
        [items addObject:[self toggle:@"ENABLED" key:[configuration isEqual:@"top"] ? kMTPanelTopEnabled : kMTPanelBottomEnabled]];
        for (NSString *direction in @[@"left", @"right"]) {
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:MTGestureLocalized([direction isEqual:@"left"] ? @"STATUS_BAR_LEFTSWIPE" : @"STATUS_BAR_RIGHTSWIPE") target:self set:nil get:@selector(readActionName:) detail:MTPToolbarBindingController.class cell:PSLinkCell edit:nil];
            [link setProperty:configuration forKey:@"toolbarConfiguration"]; [link setProperty:direction forKey:@"toolbarDirection"]; [items addObject:link];
        }
    }
    _specifiers = items;
    return _specifiers;
}
- (id)readActionName:(PSSpecifier *)specifier { return MTToolbarActionName(specifier); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    if (item.cellType == PSLinkCell && MTToolbarBindingSlot([item propertyForKey:@"toolbarConfiguration"], [item propertyForKey:@"toolbarDirection"]))
        return MTPGestureActionCell(tableView, @"MTPToolbarGestureRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator);
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
@end

@implementation MTPToolbarBindingController
- (NSString *)slot { return MTToolbarBindingSlot([self.specifier propertyForKey:@"toolbarConfiguration"], [self.specifier propertyForKey:@"toolbarDirection"]); }
- (void)viewDidLoad { [super viewDidLoad]; self.title = self.specifier.name; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTGestureLocalized(@"PANEL_TOOLBAR_FOOTER") forKey:@"footerText"];
    PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:MTGestureLocalized(@"CHOOSE_ACTION") target:self set:nil get:@selector(readActionName:) detail:nil cell:PSButtonCell edit:nil]; choose->action = @selector(chooseAction:);
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:MTGestureLocalized(@"STATUS_BAR_CLEAR") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; clear->action = @selector(clearAction:);
    _specifiers = [@[group, choose, clear] mutableCopy]; return _specifiers;
}
- (id)readActionName:(PSSpecifier *)specifier { (void)specifier; return MTToolbarActionName(self.specifier); }
- (BOOL)saveSelector:(NSString *)selector {
    NSString *slot = [self slot]; if (!slot || ![selector isKindOfClass:NSString.class]) return NO;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences || (selector.length && !MTPanelItemAllowed(preferences, selector, MTPanelKeyboardKind))) return NO;
    id stored = preferences[kMTToolbarBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    bindings[slot] = selector; preferences[kMTToolbarBindings] = bindings; [manager writePrefs:preferences];
    id latest = [manager readPrefs][kMTToolbarBindings];
    BOOL success = [latest isKindOfClass:NSDictionary.class] && [latest[slot] isEqual:selector];
    NSLog(@"[MetisKeyboard][ToolbarSettings] save slot=%@ assigned=%d success=%d", slot, selector.length > 0, success);
    [self reloadSpecifiers]; return success;
}
- (void)chooseAction:(PSSpecifier *)specifier {
    (void)specifier;
    MTPSubActionPickerController *picker = [MTPSubActionPickerController new];
    picker.actionContextKind = MTPanelKeyboardKind; picker.fullOrder = MTPPanelBuiltInActions(); picker.title = MTGestureLocalized(@"CHOOSE_ACTION");
    NSDictionary *preferences = [MTPrefsManager.sharedInstance readPrefs];
    picker.selectedSelector = MTToolbarAction(preferences, [self.specifier propertyForKey:@"toolbarConfiguration"], [self.specifier propertyForKey:@"toolbarDirection"]);
    __weak typeof(self) weakSelf = self;
    __weak MTPSubActionPickerController *weakPicker = picker;
    NSString *slot = [[self slot] copy];
    __block BOOL completed = NO;
    picker.completion = ^(NSString *selector) {
        MTPToolbarBindingController *owner = weakSelf;
        if (completed || !owner || ![slot isEqual:[owner slot]] ||
            ![owner.navigationController.viewControllers containsObject:owner] || owner.navigationController.topViewController != weakPicker) return;
        completed = [owner saveSelector:selector];
    };
    [picker setRootController:self.rootController]; [picker setParentController:self]; [self pushController:picker];
}
- (void)clearAction:(PSSpecifier *)specifier { (void)specifier; [self saveSelector:@""]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    if (item && item->action == @selector(chooseAction:)) {
        return MTPGestureActionCell(tableView, @"MTPToolbarActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator);
    }
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    if (item && (item->action == @selector(chooseAction:) || item->action == @selector(clearAction:))) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        if (item && item->action == @selector(chooseAction:)) [self chooseAction:item]; else [self clearAction:item]; return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
@end
