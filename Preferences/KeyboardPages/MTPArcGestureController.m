#import "MTPArcGestureController.h"
#import "MTPCustomActionViewController.h"
#import "MTPGestureActionCell.h"
#import "MTPPanelSliderCell.h"
#import "MTArcGesturePolicy.h"
#import "MTPanelRegistry.h"
#import "MTGlobalPanelPolicy.h"
#import "common.h"
#import <Preferences/PSSpecifier.h>

static NSString *MTArcLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSString *MTArcActionName(NSDictionary *preferences, NSString *slot) {
    NSString *selector = MTArcGestureBinding(preferences, slot)[@"selector"];
    if (MTPanelAllowed(preferences, selector, MTPanelGestureKind)) return MTPanelString(MTPanelDefinition(preferences, selector)[@"name"]);
    NSDictionary *entry = MTPanelActionDefinition(preferences, selector);
    if (!MTGlobalCustomActionSupported(entry)) return MTArcLocalized(@"STATUS_BAR_UNASSIGNED");
    NSString *name = MTPanelString(entry[@"name"]);
    return name.length ? name : MTArcLocalized(@"DEFAULT_BUTTON_NAME");
}
static BOOL MTArcSaveBinding(NSString *slot, NSString *field, id value) {
    if (!MTArcGestureSlotValid(slot) || ![@[@"selector", @"enabled", @"radius"] containsObject:field]) return NO;
    MTPrefsManager *manager = MTPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    if ([field isEqual:@"selector"] && value &&
        !MTPanelAllowed(preferences, value, MTPanelGestureKind) &&
        !MTGlobalCustomActionSupported(MTPanelActionDefinition(preferences, value))) return NO;
    id stored = preferences[kMTArcGestureBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [MTArcGestureBinding(preferences, slot) mutableCopy];
    if (value) entry[field] = value; else [entry removeObjectForKey:field];
    if ([field isEqual:@"selector"] && !value) entry[@"enabled"] = @NO;
    bindings[slot] = entry;
    preferences[kMTArcGestureBindings] = bindings;
    [manager writePrefs:preferences];
    id saved = MTArcGestureBinding([manager readPrefs], slot)[field];
    // Shared-resource "none" targets project back as an empty selector.
    return value ? [saved isEqual:value] : (saved == nil || [saved isEqual:@""]);
}

@interface MTPArcGestureEntryController : PSListController
@end
@interface MTPArcActionPickerController : MTPCustomActionViewController
@end

@implementation MTPArcActionPickerController
- (void)viewDidLoad {
    NSString *slot = [self.specifier propertyForKey:@"arcSlot"];
    self.actionContextKind = MTPanelGestureKind;
    self.requiresGlobalExecution = YES;
    self.selectionManagedExternally = YES;
    self.selectedSelector = MTArcGestureBinding([MTPrefsManager.sharedInstance readPrefs], slot)[@"selector"];
    // Configure before the shared picker loads its rows. The PSLinkCell route
    // supplies specifier/root/parent context through Preferences itself.
    self.completion = ^(NSString *selector) { MTArcSaveBinding(slot, @"selector", selector); };
    [super viewDidLoad];
    self.title = MTArcLocalized(@"CHOOSE_ACTION");
}
@end

@implementation MTPArcGestureController
- (void)viewDidLoad { [super viewDidLoad]; self.title = MTArcLocalized(@"ARC_GESTURES"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTArcLocalized(@"ARC_GESTURES_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    for (NSString *key in @[kMTArcGesturesEnabled, kMTArcGesturesLandscape]) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized([key isEqual:kMTArcGesturesEnabled] ? @"ENABLED" : @"STATUS_BAR_LANDSCAPE")
            target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [item setProperty:key forKey:@"key"];
        item.identifier = key;
        [items addObject:item];
    }
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    for (NSString *slot in MTArcGestureSlots()) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized([@"ARC_" stringByAppendingString:slot.uppercaseString])
            target:self set:nil get:nil detail:MTPArcGestureEntryController.class cell:PSLinkCell edit:nil];
        item.identifier = [[@"cornerarc-" stringByAppendingString:slot] copy];
        [item setProperty:slot forKey:@"arcSlot"];
        [items addObject:item];
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(MTArcGestureFlag([MTPrefsManager.sharedInstance readPrefs][[specifier propertyForKey:@"key"]]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) [MTPrefsManager.sharedInstance setValue:@(MTArcGestureFlag(value)) forKey:key];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    NSString *slot = [item propertyForKey:@"arcSlot"];
    if (slot.length) return MTPGestureActionCell(tableView, @"MTArcGestureRecord", item.name,
        MTArcActionName([MTPrefsManager.sharedInstance readPrefs], slot), nil, UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
@end

@implementation MTPArcGestureEntryController
- (void)viewDidLoad { [super viewDidLoad]; self.title = self.specifier.name; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:MTArcLocalized(@"ARC_ACTION_FOOTER") forKey:@"footerText"];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized(@"ENABLED") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    enabled.identifier = @"arc-enabled";
    PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized(@"CHOOSE_ACTION") target:self
        set:nil get:@selector(readActionName:) detail:MTPArcActionPickerController.class cell:PSLinkCell edit:nil];
    choose.identifier = @"arc-choose-action";
    [choose setProperty:[self.specifier propertyForKey:@"arcSlot"] forKey:@"arcSlot"];
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized(@"STATUS_BAR_CLEAR") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear.identifier = @"arc-clear-action";
    NSMutableArray *items = [@[group, enabled, choose, clear] mutableCopy];
    PSSpecifier *zoneGroup = [PSSpecifier groupSpecifierWithName:MTArcLocalized(@"ARC_ZONE")];
    [zoneGroup setProperty:MTArcLocalized(@"ARC_ZONE_FOOTER") forKey:@"footerText"];
    [items addObject:zoneGroup];
    PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized(@"ARC_RADIUS")
        target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    slider.identifier = @"arc-radius";
    [slider setProperty:@"radius" forKey:@"zoneField"];
    [slider setProperty:MTPPanelSliderCell.class forKey:@"cellClass"];
    [slider setProperty:@8 forKey:@"min"];
    [slider setProperty:@300 forKey:@"max"];
    [slider setProperty:@1 forKey:@"step"];
    [slider setProperty:@YES forKey:@"commitOnRelease"];
    [slider setProperty:@"%.0f pt" forKey:@"valueFormat"];
    [items addObject:slider];
    PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:MTArcLocalized(@"ARC_ZONE_RESET") target:self
        set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    reset.identifier = @"arc-reset-zone";
    [items addObject:reset];
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    if ([[specifier propertyForKey:@"zoneField"] isEqual:@"radius"])
        return @(MTArcGestureRadius([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"arcSlot"]));
    return @(MTArcGestureFlag(MTArcGestureBinding([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"arcSlot"])[@"enabled"]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if ([[specifier propertyForKey:@"zoneField"] isEqual:@"radius"]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        NSString *slot = [self.specifier propertyForKey:@"arcSlot"];
        double number = [value doubleValue];
        number = round(fmin([[specifier propertyForKey:@"max"] doubleValue], fmax([[specifier propertyForKey:@"min"] doubleValue], number)));
        // Slider labels track continuously; writes and dependent Y limits
        // refresh only on release, avoiding a prefs broadcast per drag tick.
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!MTArcSaveBinding(slot, @"radius", @(number))) return;
            [weakSelf reloadSpecifiers];
        });
        return;
    }
    MTArcSaveBinding([self.specifier propertyForKey:@"arcSlot"], @"enabled", @(MTArcGestureFlag(value)));
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {
    if ([[self specifierAtIndexPath:path] propertyForKey:@"zoneField"]) return 80;
    return [super tableView:tableView heightForRowAtIndexPath:path];
}
- (id)readActionName:(PSSpecifier *)specifier {
    return MTArcActionName([MTPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"arcSlot"]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    if ([item.identifier isEqual:@"arc-choose-action"])
        return MTPGestureActionCell(tableView, @"MTArcActionRecord", item.name, [self readActionName:item], nil,
            UITableViewCellAccessoryDisclosureIndicator, item);
    return [super tableView:tableView cellForRowAtIndexPath:path];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *item = [self specifierAtIndexPath:path];
    NSString *slot = [self.specifier propertyForKey:@"arcSlot"];
    if ([item.identifier isEqual:@"arc-reset-zone"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTArcSaveBinding(slot, @"radius", nil);
        [self reloadSpecifiers];
        return;
    }
    if ([item.identifier isEqual:@"arc-clear-action"]) {
        [tableView deselectRowAtIndexPath:path animated:YES];
        MTArcSaveBinding(slot, @"selector", nil);
        [self reloadSpecifiers];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:path];
}
@end
