#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Form 编码必须转义 + / =，否则 base64 的 + 会被服务端解析为空格。
FOUNDATION_EXPORT NSData *MTOCRFormBody(NSDictionary<NSString *, NSString *> *fields);
/// 只接受协议规定的文本行；空结果不生成可写入剪贴板的内容。
FOUNDATION_EXPORT NSString * _Nullable MTOCRTextFromResponse(NSDictionary *response);
/// 不向 UI/日志传递服务端原始消息（可能包含请求中的密钥或内容）。
FOUNDATION_EXPORT NSString *MTOCRBaiduErrorMessage(NSInteger code);
NS_ASSUME_NONNULL_END
