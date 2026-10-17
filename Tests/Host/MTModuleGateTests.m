// MTModuleGateTests —— 主机（macOS）侧配置门控测试。
// 覆盖：新装默认（总开、模块全关）、模块开启、总开关压制、reload 后快照一致。
#import <Foundation/Foundation.h>
#import "../../Core/MTModuleGate.h"
#import "../../Core/MTConfigService.h"

static int gFailures = 0;

static void ExpectTrue(BOOL condition, NSString *name) {
    if (condition) {
        printf("PASS %s\n", name.UTF8String);
    } else {
        printf("FAIL %s\n", name.UTF8String);
        gFailures++;
    }
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        // 1. 新装默认：总开关开、三个模块全部关闭（ADR-014）。
        [MTModuleGate reload];
        ExpectTrue([MTModuleGate globalEnabled], @"default-global-enabled");
        ExpectTrue(![MTModuleGate moduleEnabled:MTModuleCapture], @"default-capture-disabled");
        ExpectTrue(![MTModuleGate moduleEnabled:MTModuleKeyboard], @"default-keyboard-disabled");
        ExpectTrue(![MTModuleGate moduleEnabled:MTModuleClipboard], @"default-clipboard-disabled");
        ExpectTrue([MTModuleGate enabledModuleCount] == 0, @"default-count-zero");

        // 2. 写入者开启模块后读取生效。
        [MTConfigService setModule:MTModuleCapture enabled:YES];
        [MTConfigService flush];
        [MTModuleGate reload];
        ExpectTrue([MTModuleGate moduleEnabled:MTModuleCapture], @"capture-enabled-after-write");
        ExpectTrue([MTModuleGate enabledModuleCount] == 1, @"count-one");

        // 3. 总开关关闭后模块业务全部被压制（raw 开关保持）。
        [MTConfigService setGlobalEnabled:NO];
        [MTConfigService flush];
        [MTModuleGate reload];
        ExpectTrue(![MTModuleGate globalEnabled], @"global-off");
        ExpectTrue(![MTModuleGate moduleEnabled:MTModuleCapture], @"capture-suppressed-by-global");
        ExpectTrue([MTModuleGate moduleSwitchRaw:MTModuleCapture], @"capture-raw-kept");

        // 4. 恢复总开关；诊断快照包含全部键。
        [MTConfigService setGlobalEnabled:YES];
        [MTConfigService flush];
        [MTModuleGate reload];
        NSDictionary *snapshot = [MTModuleGate switchSnapshotForDiagnostics];
        ExpectTrue([snapshot count] == 4, @"snapshot-keys");
        ExpectTrue(![snapshot isKindOfClass:[NSString class]], @"snapshot-type");

        // 5. 主机进程分类：macOS 测试进程不属于任何注入宿主。
        ExpectTrue([MTModuleGate moduleEnabled:MTModuleKeyboard] == NO, @"keyboard-still-off");
    }
    return gFailures == 0 ? 0 : 1;
}
