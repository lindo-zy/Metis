//
//  MTCreditsListController.m
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import "MTCreditsListController.h"

@implementation MTCreditsListController

- (NSArray<PSSpecifier *> *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Credits" target:self];
    }

    return _specifiers;
}

@end
