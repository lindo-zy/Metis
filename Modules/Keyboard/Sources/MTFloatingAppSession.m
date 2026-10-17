#import "MTFloatingAppSession.h"

@interface MTFloatingAppSession ()
@property(nonatomic, readwrite) NSUInteger generation;
@property(nonatomic, readwrite) MTFloatingAppState state;
@property(nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property(nonatomic, copy, readwrite) NSDate *deadline;
@property(nonatomic, copy) MTSystemOpenReply reply;
@end

@implementation MTFloatingAppSession
- (NSUInteger)beginBundleIdentifier:(NSString *)bundleIdentifier deadline:(NSDate *)deadline reply:(MTSystemOpenReply)reply {
    [self finish:MTSystemOpenBusy];
    self.bundleIdentifier = bundleIdentifier;
    self.deadline = deadline;
    self.reply = reply;
    self.state = MTFloatingAppPreparing;
    return self.generation;
}
- (BOOL)isCurrent:(NSUInteger)generation {
    return generation && generation == self.generation && self.state != MTFloatingAppIdle;
}
- (BOOL)hasExpired {
    return self.state == MTFloatingAppPreparing && (!self.deadline || self.deadline.timeIntervalSinceNow <= 0);
}
- (void)publishLive:(NSUInteger)generation {
    if (![self isCurrent:generation] || self.state != MTFloatingAppPreparing || self.hasExpired) return;
    self.state = MTFloatingAppLive;
    MTSystemOpenReply reply = self.reply;
    self.reply = nil;
    if (reply) reply(MTSystemOpenSucceeded);
}
- (void)finish:(MTSystemOpenResult)result {
    self.generation++;
    if (!self.generation) self.generation = 1;
    MTSystemOpenReply reply = self.reply;
    self.reply = nil;
    self.state = MTFloatingAppIdle;
    self.bundleIdentifier = nil;
    self.deadline = nil;
    if (reply) reply(result);
}
@end
