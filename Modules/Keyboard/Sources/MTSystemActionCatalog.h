#import <Foundation/Foundation.h>

static inline NSArray<NSDictionary *> *MTSystemActionCatalog(void) {
    static NSArray *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *items = [NSMutableArray array];
        NSArray *rows = @[
            @[@"previous-track", @"SYSTEM_PREVIOUS", @"backward.end.fill", @"media"],
            @[@"next-track", @"SYSTEM_NEXT", @"forward.end.fill", @"media"],
            @[@"play-pause", @"SYSTEM_PLAY_PAUSE", @"playpause.fill", @"media"],
            @[@"respring", @"SYSTEM_RESPRING", @"arrow.clockwise", @"device"],
            @[@"respring-sb", @"SYSTEM_RESPRING_SB", @"arrow.clockwise.circle", @"device"],
            @[@"safe-mode", @"SYSTEM_SAFE_MODE", @"shield", @"device"],
            @[@"shutdown", @"SYSTEM_SHUTDOWN", @"power", @"device"],
            @[@"reboot", @"SYSTEM_REBOOT", @"restart", @"device"],
            @[@"userspace-reboot", @"SYSTEM_USERSPACE_REBOOT", @"arrow.triangle.2.circlepath", @"device"],
            @[@"home", @"SYSTEM_HOME", @"house.fill", @"device"],
            @[@"switcher", @"SYSTEM_SWITCHER", @"square.stack", @"device"],
            @[@"reachability", @"SYSTEM_REACHABILITY", @"hand.point.up.left.fill", @"device"],
            @[@"screenshot", @"SYSTEM_SCREENSHOT", @"camera.viewfinder", @"device"],
            @[@"control-center", @"SYSTEM_CONTROL_CENTER", @"switch.2", @"control"],
            @[@"screen-recording", @"SYSTEM_SCREEN_RECORDING", @"record.circle", @"control"],
            @[@"screen-recording-microphone", @"SYSTEM_SCREEN_RECORDING_MICROPHONE", @"mic.circle.fill", @"control"],
            @[@"flashlight", @"SYSTEM_FLASHLIGHT", @"flashlight.on.fill", @"control"],
            @[@"wifi", @"SYSTEM_WIFI", @"wifi", @"control"],
            @[@"bluetooth", @"SYSTEM_BLUETOOTH", @"antenna.radiowaves.left.and.right", @"control"],
            @[@"airplane", @"SYSTEM_AIRPLANE", @"airplane", @"control"],
            @[@"cellular", @"SYSTEM_CELLULAR", @"antenna.radiowaves.left.and.right", @"control"],
            @[@"orientation-lock", @"SYSTEM_ORIENTATION", @"lock.rotation", @"control"],
            @[@"do-not-disturb", @"SYSTEM_DND", @"moon.fill", @"control"],
            @[@"dark-mode", @"SYSTEM_DARK_MODE", @"circle.lefthalf.filled", @"control"],
            @[@"brightness-up", @"SYSTEM_BRIGHTNESS_UP", @"sun.max.fill", @"control"],
            @[@"brightness-down", @"SYSTEM_BRIGHTNESS_DOWN", @"sun.min.fill", @"control"],
            @[@"volume-up", @"SYSTEM_VOLUME_UP", @"speaker.plus.fill", @"control"],
            @[@"volume-down", @"SYSTEM_VOLUME_DOWN", @"speaker.minus.fill", @"control"],
            @[@"pixpin-full", @"SYSTEM_CAPTURE_FULL", @"camera.viewfinder", @"pixpin", @"com.lindo.metis.capture/full"],
            @[@"pixpin-area", @"SYSTEM_CAPTURE_AREA", @"crop", @"pixpin", @"com.lindo.metis.capture/area"],
            @[@"pixpin-markup", @"SYSTEM_CAPTURE_MARKUP", @"pencil.tip.crop.circle", @"pixpin", @"com.lindo.metis.capture/markup"],
            @[@"pixpin-long", @"SYSTEM_CAPTURE_LONG", @"rectangle.expand.vertical", @"pixpin", @"com.lindo.metis.capture/long"]
        ];
        NSSet *destructive = [NSSet setWithArray:@[@"respring", @"respring-sb", @"safe-mode", @"shutdown", @"reboot", @"userspace-reboot"]];
        for (NSArray *row in rows) {
            NSMutableDictionary *entry = [@{@"id": row[0], @"title": row[1], @"icon": row[2],
                @"group": row[3], @"destructive": @([destructive containsObject:row[0]])} mutableCopy];
            if (row.count > 4) entry[@"captureNotification"] = row[4];
            [items addObject:[entry copy]];
        }
        catalog = [items copy];
    });
    return catalog;
}

// Keep definitions stable for saved actions, but hide optional candidates when
// the tweak is absent. Re-evaluate installation whenever the picker appears.
static inline NSArray<NSDictionary *> *MTVisibleSystemActionCatalog(BOOL pixPinInstalled) {
    if (pixPinInstalled) return MTSystemActionCatalog();
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *entry in MTSystemActionCatalog())
        if (!entry[@"captureNotification"]) [visible addObject:entry];
    return [visible copy];
}

static inline BOOL MTSystemActionIsRecording(NSString *action) {
    return [action isEqual:@"screen-recording"] || [action isEqual:@"screen-recording-microphone"];
}

static inline NSDictionary *MTSystemActionDefinition(id action) {
    if (![action isKindOfClass:NSString.class]) return nil;
    for (NSDictionary *entry in MTSystemActionCatalog()) if ([entry[@"id"] isEqual:action]) return entry;
    return nil;
}

// A request must refer to an action actually saved in the authoritative
// custom definitions. Never accept selectors or command strings from clients.
static inline BOOL MTSystemActionIsConfigured(id definitions, NSString *identifier, NSString *prefix) {
    if (!MTSystemActionDefinition(identifier) || ![definitions isKindOfClass:NSArray.class] || !prefix.length) return NO;
    for (id entry in definitions) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id selector = entry[@"selector"];
        if ([selector isKindOfClass:NSString.class] && [selector hasPrefix:prefix] && [selector length] > prefix.length &&
            [entry[@"type"] isEqual:@"system"] && [entry[@"systemaction"] isEqual:identifier]) return YES;
    }
    return NO;
}
