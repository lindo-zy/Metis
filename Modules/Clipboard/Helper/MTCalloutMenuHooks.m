//
//  MTCalloutMenuHooks.m
//  Mt
//

#define CHUseSubstrate

#import "MTClipboardHelperHookInstaller.h"
#import "MTClipboardHelperRuntime.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIMenu (Mt)
- (UIMenu *)menuByReplacingChildren:(NSArray<UIMenuElement *> *)children;
@end

@interface _UICalloutBarSystemButtonDescription : NSObject
@property(nonatomic, readonly) SEL action;
+ (instancetype)buttonDescriptionWithTitle:(NSString *)arg1 action:(SEL)arg2 type:(int)arg3;
@end

@interface UICalloutBar : UIView
@end

CHDeclareClass(_UIEditMenuPresentation);
CHDeclareClass(UICalloutBar);

static NSString *const kMTAppleMenuIdentifier = @"com.apple.menu.standard-edit";
static NSString *const kMTMenuName = @"Metis";
static NSString *const kMTMenuActionSelectorName = @"_Mt_OpenTools_ab2e39c7";

static SEL mtMenuActionSelector(void) { return NSSelectorFromString(kMTMenuActionSelectorName); }

static void mtOpenMtResponderAction(id self, SEL _cmd) {
    if ([self isKindOfClass:[UIResponder class]]) {
        [[MTClipboardHelperRuntime sharedRuntime] activateMtFromResponder:self];
    } else {
        [[MTClipboardHelperRuntime sharedRuntime] activateMt];
    }
}

CHOptimizedMethod2(self, void, _UIEditMenuPresentation, displayMenu, UIMenu *, menu, configuration, id, configuration) {
    NSMutableArray<UIMenuElement *> *build = [NSMutableArray new];
    for (id item in [menu children]) {
        BOOL itemIsMtMenuItem = NO;
        if ([item isKindOfClass:[UIMenu class]]) {
            itemIsMtMenuItem = [[(UIMenu *)item title] isEqualToString:kMTMenuName];
        } else if ([item isKindOfClass:[UIAction class]]) {
            itemIsMtMenuItem = [[(UIAction *)item title] isEqualToString:kMTMenuName];
        } else if ([item isKindOfClass:[UICommand class]]) {
            NSString *selectorName = NSStringFromSelector([(UICommand *)item action]);
            itemIsMtMenuItem = [selectorName isEqualToString:kMTMenuActionSelectorName];
        }
        if (itemIsMtMenuItem) {
            continue;
        }
        if (![item isKindOfClass:[UIMenu class]]) {
            [build addObject:item];
            continue;
        }
        UIMenu *submenu = item;
        if (![submenu.identifier isEqualToString:kMTAppleMenuIdentifier]) {
            [build addObject:submenu];
            continue;
        }
        NSMutableArray<UIMenuElement *> *rebuildAppleEditMenu = [submenu.children mutableCopy];
        static UICommand *mtMenuCommand = nil;
        if (!mtMenuCommand) {
            mtMenuCommand = [UICommand commandWithTitle:kMTMenuName
                                                      image:nil
                                                     action:mtMenuActionSelector()
                                               propertyList:nil];
        }
        [rebuildAppleEditMenu addObject:mtMenuCommand];
        UIMenu *rebuildAppleMenu = [submenu menuByReplacingChildren:rebuildAppleEditMenu];
        [build addObject:rebuildAppleMenu];
    }
    UIMenu *newMenu = [menu menuByReplacingChildren:build];
    CHSuper2(_UIEditMenuPresentation, displayMenu, newMenu, configuration, configuration);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
CHOptimizedMethod1(self, void, UICalloutBar, setExtraItems, NSArray<UIMenuItem *> *, items) {
    NSMutableArray<UIMenuItem *> *newItems = [NSMutableArray arrayWithCapacity:items.count];
    for (UIMenuItem *item in items) {
        NSString *selectorName = NSStringFromSelector(item.action);
        if ([selectorName isEqualToString:kMTMenuActionSelectorName]) {
            item.action = NSSelectorFromString(@"mtDummyAction");
        }
        [newItems addObject:item];
    }
    CHSuper1(UICalloutBar, setExtraItems, [newItems copy]);
}
#pragma clang diagnostic pop

CHOptimizedMethod0(self, void, UICalloutBar, updateAvailableButtons) {
    Class cbsbdCls = NSClassFromString(@"_UICalloutBarSystemButtonDescription");
    if (!cbsbdCls || ![cbsbdCls respondsToSelector:@selector(buttonDescriptionWithTitle:action:type:)]) {
        return CHSuper0(UICalloutBar, updateAvailableButtons);
    }

    _UICalloutBarSystemButtonDescription *buttonDescription =
        [cbsbdCls buttonDescriptionWithTitle:kMTMenuName action:mtMenuActionSelector() type:1];

    if (!buttonDescription) {
        return CHSuper0(UICalloutBar, updateAvailableButtons);
    }

    Ivar msbd = class_getInstanceVariable(object_getClass(self), "m_systemButtonDescriptions");
    if (!msbd) {
        return CHSuper0(UICalloutBar, updateAvailableButtons);
    }

    NSMutableArray<_UICalloutBarSystemButtonDescription *> *buttonDescriptions = object_getIvar(self, msbd);
    for (_UICalloutBarSystemButtonDescription *description in buttonDescriptions) {
        if (!description.action) {
            continue;
        }
        NSString *selectorName = NSStringFromSelector(description.action);
        if ([selectorName isEqualToString:NSStringFromSelector(buttonDescription.action)]) {
            return CHSuper0(UICalloutBar, updateAvailableButtons);
        }
    }

    NSInteger insertIndex = NSNotFound;
    NSInteger currentIndex = 0;
    for (_UICalloutBarSystemButtonDescription *description in buttonDescriptions) {
        if (!description.action) {
            continue;
        }
        if ([NSStringFromSelector(description.action) hasPrefix:@"_"]) {
            insertIndex = currentIndex;
            break;
        }
        currentIndex++;
    }

    if (insertIndex == 0) {
        return CHSuper0(UICalloutBar, updateAvailableButtons);
    }

    if (insertIndex == NSNotFound) {
        [buttonDescriptions addObject:buttonDescription];
    } else {
        [buttonDescriptions insertObject:buttonDescription atIndex:insertIndex];
    }

    return CHSuper0(UICalloutBar, updateAvailableButtons);
}

@implementation MTClipboardHelperHookInstaller (CalloutMenu)

+ (void)installCalloutBarHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      class_addMethod(NSClassFromString(@"UIResponder"), mtMenuActionSelector(),
                      (IMP)mtOpenMtResponderAction, "v@:");

      if (@available(iOS 16, *)) {
          Class targetCls = NSClassFromString(@"_UIEditMenuContentPresentation");
          if (!targetCls) {
              targetCls = NSClassFromString(@"_UIEditMenuPresentation");
          }
          CHLoadClass_(&_UIEditMenuPresentation$, targetCls);
          CHHook2(_UIEditMenuPresentation, displayMenu, configuration);
      } else {
          CHLoadClass_(&UICalloutBar$, NSClassFromString(@"UICalloutBar"));
          CHHook1(UICalloutBar, setExtraItems);
          CHHook0(UICalloutBar, updateAvailableButtons);
      }
    });
}

@end
