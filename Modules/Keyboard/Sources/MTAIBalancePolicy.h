#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// Balance APIs are vendor-specific. Never send a key to an inferred billing host.
static inline NSURL *MTAIBalanceURL(NSString *endpoint) {
    NSURLComponents *url = [NSURLComponents componentsWithString:endpoint ?: @""];
    if (![url.scheme.lowercaseString isEqual:@"https"] || url.user || url.password ||
        url.port || url.query || url.fragment) return nil;
    NSString *host = url.host.lowercaseString;
    if ([host isEqual:@"api.deepseek.com"] &&
        [@[@"", @"/", @"/v1", @"/v1/"] containsObject:url.path ?: @""]) url.path = @"/user/balance";
    else if ([host isEqual:@"api.siliconflow.cn"] &&
             [@[@"/v1", @"/v1/"] containsObject:url.path ?: @""]) url.path = @"/v1/user/info";
    else return nil;
    return url.URL;
}

static inline NSString *MTAIBalanceAmount(id value) {
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return nil;
    NSString *text = [value description];
    if (text.length == 0 || text.length > 64 ||
        [text rangeOfString:@"^-?[0-9]+(?:\\.[0-9]+)?$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    return text;
}

// Return nil on malformed/error envelopes. Zero is a valid balance, never an error fallback.
static inline NSString *MTAIBalanceDisplay(id response, NSURL *url) {
    if (![response isKindOfClass:NSDictionary.class]) return nil;
    if ([url.host.lowercaseString isEqual:@"api.deepseek.com"]) {
        id infos = response[@"balance_infos"];
        if (![infos isKindOfClass:NSArray.class] || [infos count] == 0) return nil;
        NSMutableArray *parts = [NSMutableArray array];
        for (id info in infos) {
            if (![info isKindOfClass:NSDictionary.class]) return nil;
            NSString *amount = MTAIBalanceAmount(info[@"total_balance"]);
            NSString *currency = info[@"currency"];
            if (!amount || ![@[@"CNY", @"USD"] containsObject:currency ?: @""]) return nil;
            [parts addObject:[NSString stringWithFormat:@"%@ %@", amount, currency]];
        }
        return [parts componentsJoinedByString:@" / "];
    }
    if ([url.host.lowercaseString isEqual:@"api.siliconflow.cn"]) {
        id status = response[@"status"], code = response[@"code"];
        if ((status && (![status isKindOfClass:NSNumber.class] || ![status boolValue])) ||
            (code && (![code isKindOfClass:NSNumber.class] || [code integerValue] != 20000))) return nil;
        id data = response[@"data"];
        NSString *amount = [data isKindOfClass:NSDictionary.class] ? MTAIBalanceAmount(data[@"totalBalance"]) : nil;
        return amount ? [amount stringByAppendingString:@" CNY"] : nil;
    }
    return nil;
}
