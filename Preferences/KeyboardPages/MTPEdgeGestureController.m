#import "MTPEdgeGestureController.h"
#import "MTPCustomActionViewController.h"
#import "MTPGestureActionCell.h"
#import "MTEdgeGesturePolicy.h"
#import "MTPanelRegistry.h"
#import "MTGlobalPanelPolicy.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTEdgeLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSString *MTEdgeActionName(NSDictionary *preferences, NSString *slot) {
    NSString *selector = MTEdgeGestureBinding(preferences, slot)[@"selector"];
    if (MTPanelAllowed(preferences, selector, MTPanelGestureKind)) return MTPanelString(MTPanelDefinition(preferences, selector)[@"name"]);
    NSDictionary *entry = MTPanelActionDefinition(preferences, selector);
    if (!MTGlobalCustomActionSupported(entry)) return MTEdgeLocalized(@"STATUS_BAR_UNASSIGNED");
    NSString *name = MTPanelString(entry[@"name"]);
    return name.length ? name : MTEdgeLocalized(@"DEFAULT_BUTTON_NAME");
}
static BOOL MTEdgeSaveBinding(NSString *slot, NSString *field, id value) {
    if (!MTEdgeGestureSlotValid(slot) || ![@[@"selector", @"enabled"] containsObject:field]) return NO;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    if ([field isEqual:@"selector"] && value &&
        !MTPanelAllowed(preferences, value, MTPanelGestureKind) &&
        !MTGlobalCustomActionSupported(MTPanelActionDefinition(preferences, value))) return NO;
    id stored = preferences[kMTEdgeGestureBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [MTEdgeGestureBinding(preferences, slot) mutableCopy];
    if (value) entry[field] = value; else [entry removeObjectForKey:field];
    if ([field isEqual:@"selector"] && !value) entry[@"enabled"] = @NO;
    bindings[slot] = entry;
    preferences[kMTEdgeGestureBindings] = bindings;
    [manager writePrefs:preferences];
    id saved = MTEdgeGestureBinding([manager readPrefs], slot)[field];
    return value ? [saved isEqual:value] : saved == nil;
}

@interface MTPEdgeGestureEntryController : PSListController
@end

@implementation MTPEdgeGestureController
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTEdgeLocalized(@"EDGE_GESTURES"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTEdgeLocalized(@"EDGE_GESTURES_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    for (NSString *key in @[kMTEdgeGesturesEnabled, kMTEdgeGesturesLandscape]) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized([key isEqual:kMTEdgeGesturesEnabled] ? @"ENABLED" : @"STATUS_BAR_LANDSCAPE")
            target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [item setProperty:key forKey:@"key"];
        item.identifier = key;
        [items addObject:item];
    }
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    for (NSString *slot in MTEdgeGestureSlots()) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized([@"EDGE_" stringByAppendingString:slot.uppercaseString])
            target:self set:nil get:nil detail:MTPEdgeGestureEntryController.class cell:PSLinkCell edit:nil];
        item.identifier = [@"screenedge-" stringByAppendingString:slot];
        [item setProperty:slot forKey:@"edgeSlot"];
        [items addObject:item];
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTEdgeGestureFlag([MTPrefsManager.sharedInstance readPrefs][[specifier propertyForKey:@"key"]]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) [MTPrefsManager.sharedInstance setValue:@(MTEdgeGestureFlag(value)) forKey:key];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    NSString *slot = [item propertyForKey:@"edgeSlot"];
    if (slot.length) return MTPGestureActionCell(tableView, @"MTEdgeGestureRecord", item.name,
        MTEdgeActionName([MTPrefsManager.sharedInstance readPrefs], slot), nil, UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
@end

@implementation MTPEdgeGestureEntryController
- (void)viewDidLoad { [super viewDidLoad]; self.title = self.specifier.name; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTEdgeLocalized(@"EDGE_ACTION_FOOTER") forKey:@"footerText"];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"ENABLED") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    enabled.identifier = @"edge-enabled";
    PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"CHOOSE_ACTION") target:self
        set:nil get:@selector(readActionName:) detail:nil cell:PSLinkCell edit:nil];
    choose.identifier = @"edge-choose-action";
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"STATUS_BAR_CLEAR") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear.identifier = @"edge-clear-action";
    _specifiers = @[group, enabled, choose, clear]; return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTEdgeGestureFlag(MTEdgeGestureBinding([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"])[@"enabled"]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    MTEdgeSaveBinding([self.specifier propertyForKey:@"edgeSlot"], @"enabled", @(MTEdgeGestureFlag(value)));
}
- (id)readActionName:(PSSpecifier *)specifier {
    return MTEdgeActionName([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"]);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    NSString *slot = [self.specifier propertyForKey:@"edgeSlot"];
    if ([item.identifier isEqual:@"edge-clear-action"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTEdgeSaveBinding(slot, @"selector", nil);
        [self reloadSpecifiers];
        return;
    }
    if ([item.identifier isEqual:@"edge-choose-action"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTPCustomActionViewController *picker = [MTPCustomActionViewController new];
        picker.actionContextKind = MTPanelGestureKind;
        picker.requiresGlobalExecution = YES;
        picker.selectionManagedExternally = YES;
        picker.selectedSelector = MTEdgeGestureBinding([MTPrefsManager.sharedInstance readPrefs], slot)[@"selector"];
        picker.title = MTEdgeLocalized(@"CHOOSE_ACTION");
        // Shared actions are authored in Global Settings; this page writes a reference only.
        picker.completion = ^(NSString *selector) { MTEdgeSaveBinding(slot, @"selector", selector); };
        [picker setRootController:self.rootController];
        [picker setParentController:self];
        [self pushController:picker];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
@end
