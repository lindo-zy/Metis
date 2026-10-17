// MTPathResolver.h —— 逻辑路径到 RootHide 实路径的唯一解析入口
// （03-architecture §9：不拼接 .jbroot UUID，不硬编码 /var/jb）。
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 把形如 /Library/Metis/... 的逻辑路径解析为当前越狱环境真实路径。
/// roothide 环境经 jbroot() 解析；其余环境原样返回。
NSString *MTResolvePath(NSString *logicalPath);

/// Metis 私有数据根（逻辑路径 /var/mobile/Library/Metis/）。
NSString *MTPrivateDataRoot(void);

/// Metis 公共只读快照目录（逻辑路径 /Library/Metis/Config/）。
NSString *MTPublicConfigDirectory(void);

NS_ASSUME_NONNULL_END
