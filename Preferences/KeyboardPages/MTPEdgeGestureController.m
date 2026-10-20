#import "MTPEdgeGestureController.h"
#import "MTPCustomActionViewController.h"
#import "MTPGestureActionCell.h"
#import "MTPPanelSliderCell.h"
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
    if (!MTEdgeGestureSlotValid(slot) || ![@[@"selector", @"enabled", @"range"] containsObject:field]) return NO;
    if ([field isEqual:@"range"]) value = MTEdgeNormalizedRange(value);
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
    // Shared-resource "none" targets project back as an empty selector.
    return value ? [saved isEqual:value] : (saved == nil || [saved isEqual:@""]);
}

@interface MTPEdgeGestureEntryController : PSListController
@end
@interface MTPEdgeActionPickerController : MTPCustomActionViewController
@end

@implementation MTPEdgeActionPickerController
- (void)viewDidLoad {
    NSString *slot = [self.specifier propertyForKey:@"edgeSlot"];
    self.actionContextKind = MTPanelGestureKind;
    self.requiresGlobalExecution = YES;
    self.selectionManagedExternally = YES;
    self.selectedSelector = MTEdgeGestureBinding([MTPrefsManager.sharedInstance readPrefs], slot)[@"selector"];
    // Configure before the shared picker loads its rows. The PSLinkCell route
    // supplies specifier/root/parent context through Preferences itself.
    self.completion = ^(NSString *selector) { MTEdgeSaveBinding(slot, @"selector", selector); };
    [super viewDidLoad];
    self.title = MTEdgeLocalized(@"CHOOSE_ACTION");
}
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
    PSSpecifier *debugGroup = [PSSpecifier groupSpecifierWithName:nil];
    [debugGroup setProperty:MTEdgeLocalized(@"EDGE_DEBUG_FOOTER") forKey:@"footerText"];
    [items addObject:debugGroup];
    PSSpecifier *debug = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"EDGE_DEBUG") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    debug.identifier = kMTEdgeGesturesDebug;
    [debug setProperty:kMTEdgeGesturesDebug forKey:@"key"];
    [items addObject:debug];
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
        set:nil get:@selector(readActionName:) detail:MTPEdgeActionPickerController.class cell:PSLinkCell edit:nil];
    choose.identifier = @"edge-choose-action";
    [choose setProperty:[self.specifier propertyForKey:@"edgeSlot"] forKey:@"edgeSlot"];
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"STATUS_BAR_CLEAR") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear.identifier = @"edge-clear-action";
    NSMutableArray *items = [@[group, enabled, choose, clear] mutableCopy];
    PSSpecifier *rangeGroup = [PSSpecifier groupSpecifierWithName:MTEdgeLocalized(@"EDGE_RANGE")];
    [rangeGroup setProperty:MTEdgeLocalized(@"EDGE_RANGE_FOOTER") forKey:@"footerText"];
    [items addObject:rangeGroup];
    NSDictionary *range = MTEdgeGestureRange([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"]);
    for (NSString *field in @[@"width", @"yStart", @"yEnd", @"distance"]) {
        PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized([@"EDGE_RANGE_" stringByAppendingString:field.uppercaseString])
            target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
        slider.identifier = [@"edge-range-" stringByAppendingString:field];
        [slider setProperty:field forKey:@"rangeField"];
        [slider setProperty:MTPPanelSliderCell.class forKey:@"cellClass"];
        double minimum = [field isEqual:@"width"] ? 1 : ([field isEqual:@"distance"] ? 20 :
            ([field isEqual:@"yEnd"] ? [range[@"yStart"] doubleValue] + 1 : 0));
        double maximum = [field isEqual:@"width"] ? 80 : ([field isEqual:@"distance"] ? 240 :
            ([field isEqual:@"yStart"] ? [range[@"yEnd"] doubleValue] - 1 : 100));
        [slider setProperty:@(minimum) forKey:@"min"];
        [slider setProperty:@(maximum) forKey:@"max"];
        [slider setProperty:@1 forKey:@"step"];
        [slider setProperty:@YES forKey:@"commitOnRelease"];
        [slider setProperty:[field hasPrefix:@"y"] ? @"%.0f%%" : @"%.0f pt" forKey:@"valueFormat"];
        [items addObject:slider];
    }
    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:MTEdgeLocalized(@"EDGE_RANGE_RESET") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    reset.identifier = @"edge-reset-range";
    [items addObject:reset];
    _specifiers = items; return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *field = [specifier propertyForKey:@"rangeField"];
    if (field.length) return MTEdgeGestureRange([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"])[field];
    return @(MTEdgeGestureFlag(MTEdgeGestureBinding([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"])[@"enabled"]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *field = [specifier propertyForKey:@"rangeField"];
    if (field.length) {
        if (![value isKindOfClass:NSNumber.class]) return;
        NSString *slot = [self.specifier propertyForKey:@"edgeSlot"];
        NSMutableDictionary *range = [MTEdgeGestureRange([MTPrefsManager.sharedInstance readPrefs], slot) mutableCopy];
        double number = MTEdgeRangeNumber(value, [range[field] doubleValue], [[specifier propertyForKey:@"min"] doubleValue], [[specifier propertyForKey:@"max"] doubleValue]);
        range[field] = @(number);
        MTEdgeSaveBinding(slot, @"range", range);
        // Slider labels track continuously; writes and dependent Y limits
        // refresh only on release, avoiding a prefs broadcast per drag tick.
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadSpecifiers]; });
        return;
    }
    MTEdgeSaveBinding([self.specifier propertyForKey:@"edgeSlot"], @"enabled", @(MTEdgeGestureFlag(value)));
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    if ([[self specifierAtIndexPath:path] propertyForKey:@"rangeField"]) return 80;
    return [super tableView:tableView heightForRowAtIndexPath:path];
}
- (id)readActionName:(PSSpecifier *)specifier {
    return MTEdgeActionName([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"edgeSlot"]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    if ([item.identifier isEqual:@"edge-choose-action"])
        return MTPGestureActionCell(tableView, @"MTEdgeActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    NSString *slot = [self.specifier propertyForKey:@"edgeSlot"];
    if ([item.identifier isEqual:@"edge-reset-range"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTEdgeSaveBinding(slot, @"range", @{});
        [self reloadSpecifiers];
        return;
    }
    if ([item.identifier isEqual:@"edge-clear-action"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTEdgeSaveBinding(slot, @"selector", nil);
        [self reloadSpecifiers];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
@end
