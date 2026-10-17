#pragma once
#import <Foundation/Foundation.h>

#define kMTSMSCodeEnabledKey @"smscodecopyBOOL"

FOUNDATION_EXPORT BOOL MTSMSCodePreferencesEnabled(NSDictionary *preferences);
FOUNDATION_EXPORT NSString *MTSMSExtractCode(NSString *text);

// Main-thread confined. No message text or codes are persisted here.
@interface MTSMSCodeSession : NSObject
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) NSUInteger generation;
- (void)updatePreferences:(NSDictionary *)preferences now:(NSDate *)now;
- (BOOL)acceptMessageID:(NSString *)messageID date:(NSDate *)date now:(NSDate *)now;
@end
