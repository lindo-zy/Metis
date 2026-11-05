#import "MTDeviceFrameTemplate.h"
#import <math.h>

@implementation MTDeviceFrameTemplate
+ (NSArray<MTDeviceFrameTemplate *> *)builtInTemplates {
    static NSArray *items;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *result = [NSMutableArray new];
        NSArray *ids = @[@"island",@"notch",@"classic"];
        NSArray *names = @[@"灵动岛",@"刘海",@"经典 Home"];
        for (NSInteger i = 0; i < 3; i++) {
            MTDeviceFrameTemplate *t = [self new];
            t->_identifier = ids[i]; t->_name = names[i]; t->_kind = i;
            t->_canvasSize = i == 2 ? CGSizeMake(405, 817) : CGSizeMake(423, 882);
            t->_screenQuad = MTDeviceFrameQuadForRect(i == 2 ? CGRectMake(15,75,375,667) : CGRectMake(15,15,393,852));
            [result addObject:t];
        }
        items = [result copy];
    });
    return items;
}
+ (NSDictionary *)parseConfigurationData:(NSData *)data {
    if (data.length == 0 || data.length > 65536) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class])
        value = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
    if ([value isKindOfClass:NSDictionary.class]) return value;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:spaces];
        if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@";"]) continue;
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location == NSNotFound) return nil;
        NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:spaces];
        NSString *string = [[line substringFromIndex:equals.location+1] stringByTrimmingCharactersInSet:spaces];
        if (!key.length || dictionary[key]) return nil;
        if ([key isEqualToString:@"name"]) { dictionary[key] = string; continue; }
        NSScanner *scanner = [NSScanner scannerWithString:string];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        double number = 0;
        if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return nil;
        dictionary[key] = @(number);
    }
    return dictionary.count ? dictionary : nil;
}
+ (instancetype)customTemplateWithDictionary:(NSDictionary *)d identifier:(NSString *)identifier overlayPath:(NSString *)path {
    if (![d isKindOfClass:NSDictionary.class] || !identifier.length || !path.length) return nil;
    NSArray *keys = @[@"template_width",@"template_height",@"left_top_x",@"left_top_y",@"right_top_x",@"right_top_y",
                      @"right_bottom_x",@"right_bottom_y",@"left_bottom_x",@"left_bottom_y"];
    CGFloat n[10];
    for (NSUInteger i=0; i<keys.count; i++) {
        id value = d[keys[i]];
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
        n[i] = [value doubleValue];
        if (!isfinite(n[i])) return nil;
    }
    CGSize canvas = CGSizeMake(n[0],n[1]);
    MTDeviceFrameQuad q = {CGPointMake(n[2],n[3]),CGPointMake(n[4],n[5]),CGPointMake(n[6],n[7]),CGPointMake(n[8],n[9])};
    if (!MTDeviceFrameValidQuad(q, canvas) || floor(canvas.width) != canvas.width || floor(canvas.height) != canvas.height) return nil;
    MTDeviceFrameTemplate *t = [self new];
    t->_identifier = [identifier copy]; t->_overlayPath = [path copy]; t->_canvasSize = canvas; t->_screenQuad = q; t->_kind = 3;
    NSString *name = [d[@"name"] isKindOfClass:NSString.class] ? d[@"name"] : @"自定义机壳";
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) name = @"自定义机壳";
    t->_name = [name substringToIndex:MIN(name.length,32)];
    return t;
}
- (NSDictionary *)dictionaryRepresentation {
    MTDeviceFrameQuad q = self.screenQuad;
    return @{@"name":self.name,@"template_width":@(self.canvasSize.width),@"template_height":@(self.canvasSize.height),
        @"left_top_x":@(q.topLeft.x),@"left_top_y":@(q.topLeft.y),@"right_top_x":@(q.topRight.x),@"right_top_y":@(q.topRight.y),
        @"right_bottom_x":@(q.bottomRight.x),@"right_bottom_y":@(q.bottomRight.y),
        @"left_bottom_x":@(q.bottomLeft.x),@"left_bottom_y":@(q.bottomLeft.y)};
}
@end
