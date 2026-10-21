#import "MTContextTypes.h"

// 纯判定层：只吃快照，不读时钟、不碰 UI、不改状态。
// 放在这里而不是 View 里，是为了让「哪一组该亮」可以脱离设备单测与复现。
@interface MTContextGroupEngine : NSObject

+ (MTContextDecision *)decisionForSnapshot:(MTContextSnapshot *)snapshot config:(MTContextGroupConfig *)config;
+ (MTContextDecision *)decisionForSnapshot:(MTContextSnapshot *)snapshot
                                  settings:(MTContextGroupSettings *)settings;

@end

FOUNDATION_EXPORT BOOL MTContextGroupIsActive(MTContextSnapshot *snapshot, MTContextGroupConfig *config, MTContextGroup group);

// 内容识别：选区/剪贴板共用一套判定，避免两处规则漂移。
// 含空白、无 scheme 的串不当作链接；数字串不会被误判成域名。
FOUNDATION_EXPORT NSURL *MTContextURLForText(NSString *text);
FOUNDATION_EXPORT BOOL MTContextTextLooksLikePhone(NSString *text);
FOUNDATION_EXPORT BOOL MTContextTextLooksLikeCode(NSString *text);
