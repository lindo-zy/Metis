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
/// 目录由包 staged 为 0777：Settings 写入门控快照，沙盒进程只读。
NSString *MTPublicConfigDirectory(void);

/// 门控快照文件（MTPublicConfigDirectory 下）：承载 enabled 与三个模块
/// 开关，供沙盒宿主（app/键盘扩展，读不到 /var/mobile 偏好文件）获取
/// com.lindo.metis 门控的镜像。唯一写入者是 MTConfigService.flush。
NSString *MTGateSnapshotPath(void);

NS_ASSUME_NONNULL_END
