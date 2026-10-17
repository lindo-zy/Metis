#import "DXFloatingAppSession.h"

@interface DXFloatingAppSession ()
@property(nonatomic, readwrite) NSUInteger generation;
@property(nonatomic, readwrite) DXFloatingAppState state;
@property(nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property(nonatomic, copy, readwrite) NSDate *deadline;
@property(nonatomic, copy) DXSystemOpenReply reply;
@end

@implementation DXFloatingAppSession
- (NSUInteger)beginBundleIdentifier:(NSString *)bundleIdentifier deadline:(NSDate *)deadline reply:(DXSystemOpenReply)reply {
    [self finish:DXSystemOpenBusy];
    self.bundleIdentifier = bundleIdentifier;
    self.deadline = deadline;
    self.reply = reply;
    self.state = DXFloatingAppPreparing;
    return self.generation;
}
- (BOOL)isCurrent:(NSUInteger)generation {
    return generation && generation == self.generation && self.state != DXFloatingAppIdle;
}
- (BOOL)hasExpired {
    return self.state == DXFloatingAppPreparing && (!self.deadline || self.deadline.timeIntervalSinceNow <= 0);
}
- (void)publishLive:(NSUInteger)generation {
    if (![self isCurrent:generation] || self.state != DXFloatingAppPreparing || self.hasExpired) return;
    self.state = DXFloatingAppLive;
    DXSystemOpenReply reply = self.reply;
    self.reply = nil;
    if (reply) reply(DXSystemOpenSucceeded);
}
- (void)finish:(DXSystemOpenResult)result {
    self.generation++;
    if (!self.generation) self.generation = 1;
    DXSystemOpenReply reply = self.reply;
    self.reply = nil;
    self.state = DXFloatingAppIdle;
    self.bundleIdentifier = nil;
    self.deadline = nil;
    if (reply) reply(result);
}
@end
