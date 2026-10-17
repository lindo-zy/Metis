// MTGlobals.h —— 原 MTKeyboardHooks.xm 顶层的跨文件全局（Metis 迁移说明）。
// 这些符号被 Core 共享类与 SB/UIKit 两侧入口同时读写；为保证与原单镜像
// 行为一致，定义唯一化到 MetisCore 的 MTGlobals.m，各镜像只持 extern。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MTKeyboardUIKit.h"

extern id delegate;
extern UIKeyboardImpl *kbImpl;
extern UIColor *currentTintColor;
extern UIColor *currentBackgroundTintColor;
extern BOOL isLandscape;
extern NSMutableDictionary *prefs;
extern BOOL isDictating;
extern BOOL toggledOn;
extern UIKeyboardDockView *dockView;
extern BOOL singleTapDictationEnabled;
extern BOOL singleTapGlobeEnabled;
extern BOOL isSpringBoard;
extern BOOL isApplication;
extern BOOL isSafari;
extern UIKeyboardDockView *dockV;
extern NSBundle *tweakBundle;
extern BOOL firstInit;
