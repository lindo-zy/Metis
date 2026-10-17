// MTGlobals.m —— MetisKeyboard 全局唯一定义（编译进 MetisCore，见 MTGlobals.h）。
#import "MTGlobals.h"
#import "common.h"

id delegate = nil;
UIKeyboardImpl *kbImpl = nil;
UIColor *currentTintColor = nil;
UIColor *currentBackgroundTintColor = nil;
BOOL isLandscape = NO;
NSMutableDictionary *prefs = nil;
BOOL isDictating = NO;
BOOL toggledOn = YES;
UIKeyboardDockView *dockView = nil;
BOOL singleTapDictationEnabled = NO;
BOOL singleTapGlobeEnabled = NO;
BOOL isSpringBoard = YES;
BOOL isApplication = NO;
BOOL isSafari = NO;
UIKeyboardDockView *dockV = nil;
NSBundle *tweakBundle = nil;
BOOL firstInit = YES;
MTStudlyCapsType spongebobEntropy = 0;
