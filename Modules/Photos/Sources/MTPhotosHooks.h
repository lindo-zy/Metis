// MTPhotosHooks —— 照片 App（com.apple.mobileslideshow）相册增强运行时入口。
// 仅 MetisUIKit ctor 识别到照片进程时调用；其他 UIKit 进程零开销
// （03-architecture：不新增注入目标，复用 UIKit 宿主镜像）。
void MTPhotosInstall(void);
