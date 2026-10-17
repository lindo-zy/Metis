#import "DXSMSCodePolicy.h"

BOOL DXSMSCodePreferencesEnabled(NSDictionary *preferences) {
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id feature = preferences[kDXSMSCodeEnabledKey];
    id enabled = preferences[@"enabledBOOL"];
    return [feature isKindOfClass:NSNumber.class] && [feature boolValue] &&
        (!enabled || ([enabled isKindOfClass:NSNumber.class] && [enabled boolValue]));
}

NSString *DXSMSExtractCode(NSString *text) {
    if (![text isKindOfClass:NSString.class] || !text.length || text.length > 4096) return nil;
    static NSRegularExpression *keywords, *numbers, *between, *issuer, *nonVerification;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keywords = [NSRegularExpression regularExpressionWithPattern:
            @"验证码|驗證碼|校验码|校驗碼|动态码|動態碼|动态密码|動態密碼|一次性密码|一次性密碼|(?<![a-z])(?:verification\\s+code|security\\s+code|authentication\\s+code|one[- ]time\\s+(?:code|password)|passcode|otp|code)(?![a-z])"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        numbers = [NSRegularExpression regularExpressionWithPattern:@"(?<![A-Za-z0-9])[0-9]{4,8}(?![A-Za-z0-9])"
            options:0 error:NULL];
        // Only connectors between a keyword and a number; never jump over
        // an order number, URL, money amount, date, or sentence boundary.
        between = [NSRegularExpression regularExpressionWithPattern:
            @"^(?:[\\s:：,，=【】\\[\\]（）()<>《》'\"“”‘’*-]|为|為|是|为您|為您|为你|為你|您的|你的|is|is your|your|for|to|enter|use){0,20}$"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        issuer = [NSRegularExpression regularExpressionWithPattern:
            @"^\\s+is\\s+your\\s+(?:[A-Za-z][A-Za-z0-9&.'-]{0,24}\\s+){0,2}$"
            options:NSRegularExpressionCaseInsensitive error:NULL];
        nonVerification = [NSRegularExpression regularExpressionWithPattern:
            @"(?:order|tracking|coupon|promo|postal|zip|discount|referral|product|booking|pickup|gift|reference)\\s+$"
            options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    NSRange all = NSMakeRange(0, text.length);
    NSArray<NSTextCheckingResult *> *anchors = [keywords matchesInString:text options:0 range:all];
    if (!anchors.count) return nil;
    NSMutableSet<NSString *> *candidates = [NSMutableSet set];
    for (NSTextCheckingResult *number in [numbers matchesInString:text options:0 range:all]) {
        NSRange range = number.range;
        // Reject chunks of formatted telephone numbers, decimals and dates.
        if (range.location) {
            unichar previous = [text characterAtIndex:range.location - 1];
            if (previous == '+' || previous == '-') continue;
            if ((previous == '.' || previous == '/') && range.location >= 2) {
                unichar before = [text characterAtIndex:range.location - 2];
                if (before >= '0' && before <= '9') continue;
            }
        }
        if (NSMaxRange(range) + 1 < text.length) {
            unichar next = [text characterAtIndex:NSMaxRange(range)];
            unichar after = [text characterAtIndex:NSMaxRange(range) + 1];
            if ((next == '.' || next == '/' || next == '-') && after >= '0' && after <= '9') continue;
        }
        for (NSTextCheckingResult *anchor in anchors) {
            NSString *keyword = [text substringWithRange:anchor.range];
            if ([keyword.lowercaseString isEqualToString:@"code"]) {
                NSUInteger prefixStart = anchor.range.location > 32 ? anchor.range.location - 32 : 0;
                NSRange prefix = NSMakeRange(prefixStart, anchor.range.location - prefixStart);
                if ([nonVerification firstMatchInString:text options:0 range:prefix]) continue;
            }
            NSRange gap;
            BOOL precedesKeyword = NO;
            if (NSMaxRange(anchor.range) <= range.location)
                gap = NSMakeRange(NSMaxRange(anchor.range), range.location - NSMaxRange(anchor.range));
            else if (NSMaxRange(range) <= anchor.range.location) {
                gap = NSMakeRange(NSMaxRange(range), anchor.range.location - NSMaxRange(range));
                precedesKeyword = YES;
            }
            else continue;
            if (gap.length > 24) continue;
            NSString *connector = [text substringWithRange:gap];
            if (precedesKeyword && [connector rangeOfCharacterFromSet:
                [NSCharacterSet characterSetWithCharactersInString:@",，\n\r"]].location != NSNotFound) continue;
            NSRange connectorRange = NSMakeRange(0, connector.length);
            BOOL branded = precedesKeyword && ![keyword.lowercaseString isEqualToString:@"code"] &&
                [issuer firstMatchInString:connector options:0 range:connectorRange];
            if (branded || [between firstMatchInString:connector options:0 range:connectorRange]) {
                [candidates addObject:[text substringWithRange:range]];
                break;
            }
        }
    }
    // Ambiguous messages are left alone rather than guessing a code.
    return candidates.count == 1 ? candidates.anyObject : nil;
}

@implementation DXSMSCodeSession {
    NSDate *_enabledSince;
    NSDate *_latestDate;
    NSMutableDictionary<NSString *, NSDate *> *_handled;
}
- (void)updatePreferences:(NSDictionary *)preferences now:(NSDate *)now {
    BOOL enabled = DXSMSCodePreferencesEnabled(preferences);
    if (_enabled == enabled) return;
    _enabled = enabled;
    _generation++;
    _enabledSince = enabled ? now : nil;
    _latestDate = nil;
    _handled = enabled ? [NSMutableDictionary dictionary] : nil;
}
- (BOOL)acceptMessageID:(NSString *)messageID date:(NSDate *)date now:(NSDate *)now {
    if (!_enabled || ![messageID isKindOfClass:NSString.class] || !messageID.length ||
        ![date isKindOfClass:NSDate.class] || ![now isKindOfClass:NSDate.class]) return NO;
    NSTimeInterval age = [now timeIntervalSinceDate:date];
    if (age > 120 || age < -5 || [date timeIntervalSinceDate:_enabledSince] < -1 ||
        (_latestDate && [date compare:_latestDate] == NSOrderedAscending)) return NO;
    NSString *key = [NSString stringWithFormat:@"%@/%.6f", messageID, date.timeIntervalSinceReferenceDate];
    if (_handled[key]) return NO;
    for (NSString *oldKey in _handled.allKeys)
        if ([now timeIntervalSinceDate:_handled[oldKey]] > 120) [_handled removeObjectForKey:oldKey];
    // Never evict a live duplicate and let it overwrite a subsequent manual
    // copy: stop admitting events if the bounded cache is full.
    if (_handled.count >= 128) return NO;
    _handled[key] = date;
    _latestDate = date;
    return YES;
}
@end
