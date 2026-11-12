#import "MTOCRResponse.h"

NSData *MTOCRFormBody(NSDictionary<NSString *, NSString *> *fields) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in [fields.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",
            [key stringByAddingPercentEncodingWithAllowedCharacters:allowed],
            [fields[key] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    }
    return [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
}

NSString *MTOCRTextFromResponse(NSDictionary *response) {
    if (response[@"error_code"] != nil || ![response[@"words_result"] isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (id row in response[@"words_result"]) {
        if (![row isKindOfClass:NSDictionary.class]) return nil;
        id words = row[@"words"];
        if (![words isKindOfClass:NSString.class]) return nil;
        if ([words stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            [lines addObject:words];
        }
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

NSString *MTOCRBaiduErrorMessage(NSInteger code) {
    switch (code) {
        case 110: case 111: return @"百度授权已失效，请重新识别";
        case 6: case 14: return @"百度 OCR 未开通或无权限，请检查应用配置";
        case 17: case 18: case 19: return @"百度 OCR 配额不足或请求过于频繁，请稍后重试";
        case 216201: case 216202: return @"百度无法处理这张图片，请调整区域后重试";
        default: return [NSString stringWithFormat:@"百度识别失败（%ld）", (long)code];
    }
}
