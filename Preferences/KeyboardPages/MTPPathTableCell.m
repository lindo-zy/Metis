#import "MTPPathTableCell.h"

@implementation MTPPathTableCell
- (void)prepareForReuse {
    [super prepareForReuse];
    self.specifier = nil;
}
@end
