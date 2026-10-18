LIBRARY_NAME = MetisCore

# MetisCore 是包内私有共享库：所有注入目标与设置子包都以动态链接使用它，
# 保证同一 Objective-C 类在一个进程内只有一个镜像定义（03-architecture §1）。
# 载入准则：MT* 公共类型 + 被 SB/UIKit/设置子包共同引用的 DX* 共享类
# （含 vendored AltList，ADR-011 的 vendoring 备选路径：单一副本保证类唯一）。
MetisCore_INSTALL_PATH = /Library/Metis/Frameworks
# install_name 由 Theos 的 package scheme 生成。RootHide 使用
# @loader_path/.jbroot/Library/Metis/Frameworks/MetisCore.dylib；
# 手动覆盖为 /var/jb 会让所有消费者在随机 jbroot 环境中加载失败。

MetisCore_FILES = MTLog.m \
	MTPathResolver.m \
	MTProcessContext.m \
	MTModuleGate.m \
	MTConfigService.m

# 共享资源层（docs/development/03）：动作/面板/绑定唯一权威 store、验证、
# 迁移与键盘 legacy 桥接。Foundation-only，主机测试可直接编译。
MetisCore_FILES += SharedResources/MTSharedResourceIDs.m \
	SharedResources/MTSharedResourceValidator.m \
	SharedResources/MTSharedResourceStore.m \
	SharedResources/MTSharedResourceMigration.m \
	SharedResources/MTSharedResourceLegacyBridge.m

# Keyboard（MetisKeyboard）共享层：任一被两个以上镜像引用的 DX 类都在这里。
KEYBOARD = ../Modules/Keyboard/Sources
MetisCore_FILES += $(KEYBOARD)/MTGlobals.m \
	$(KEYBOARD)/MTAIEngine.m \
	$(KEYBOARD)/MTAIMarkdown.m \
	$(KEYBOARD)/MTAIPanel.m \
	$(KEYBOARD)/MTCell.m \
	$(KEYBOARD)/MTCollectionView.m \
	$(KEYBOARD)/MTDarwinOpenChannel.m \
	$(KEYBOARD)/MTFloatingAppInput.m \
	$(KEYBOARD)/MTFloatingAppRuntime.mm \
	$(KEYBOARD)/MTFloatingAppSession.m \
	$(KEYBOARD)/MTFloatingAppShelfChannel.m \
	$(KEYBOARD)/MTFloatingAppShelfState.m \
	$(KEYBOARD)/MTFloatingAppShelfView.m \
	$(KEYBOARD)/MTGlobalActionExecutor.m \
	$(KEYBOARD)/MTGlobalPanel.m \
	$(KEYBOARD)/MTHelper.m \
	$(KEYBOARD)/MTJavaScriptEngine.m \
	$(KEYBOARD)/MTJavaScriptHost.m \
	$(KEYBOARD)/MTKbdCollapseHandle.m \
	$(KEYBOARD)/MTKeyboardPanel.m \
	$(KEYBOARD)/MTPanelControlSession.m \
	$(KEYBOARD)/MTPanelPagedGridView.m \
	$(KEYBOARD)/MTPanelSystemControlsView.m \
	$(KEYBOARD)/MTAppLauncherCatalog.m \
	$(KEYBOARD)/MTAppSearch.m \
	$(KEYBOARD)/MTQuickLauncherView.m \
	$(KEYBOARD)/MTToolbarHorizontalGesture.m \
	$(KEYBOARD)/MTPrefsManager.m \
	$(KEYBOARD)/MTQuickActionProvider.m \
	$(KEYBOARD)/MTSensitiveURLExecutor.m \
	$(KEYBOARD)/MTShared.mm \
	$(KEYBOARD)/MTShortcutsGenerator.m \
	$(KEYBOARD)/MTSystemActionExecutor.m \
	$(KEYBOARD)/MTSystemOpenBroker.m \
	$(KEYBOARD)/MTSystemRecordingSession.m \
	$(KEYBOARD)/UIImage+Resize.m

# vendored AltList（MIT，来源见 Core/AltList/README-MetisKeyboard-vendor.md）
MetisCore_FILES += $(wildcard AltList/*.m)

# 设置页 UI 套件（设计稿 metis-settings-v3.png）：模型层 Foundation-only
# （宿主测试直接编译），UIKit 渲染层由设置壳/键盘子包共用。全部走 MetisCore
# 单一镜像，维持跨 bundle 类唯一性（03-architecture §1）。
MetisCore_FILES += $(wildcard PrefsUI/*.m)

MetisCore_CFLAGS = -fobjc-arc
MetisCore_CFLAGS += -Wno-tautological-pointer-compare
MetisCore_CFLAGS += -DMETIS_PACKAGE_VERSION=\"$(or $(PACKAGE_VERSION),$(THEOS_PACKAGE_BASE_VERSION))\"
MetisCore_CFLAGS += -I. -I$(KEYBOARD) -IAltList -ISharedResources -IPrefsUI

# 共享资源 store 权威目录（Core/SharedResources）：/var/mobile/Library/Metis/Global
# 与 /Library/Metis/Config 同策略——目录 0777 无 sticky，mobile 写者（Settings /
# SpringBoard）可原子替换 root 拥有的 staged 文件。缺了它，设置端的资源提交
# （自定义动作/面板/绑定）在设备上全部失败并表现为「保存无效」。
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/var/mobile/Library/Metis/Global$(ECHO_END)
	$(ECHO_NOTHING)chmod 0777 $(THEOS_STAGING_DIR)/var/mobile/Library/Metis/Global$(ECHO_END)

# Clipboard（MetisClipboard）共享层：SwipeUp 识别器（SB+UIKit 共用）与 Shared Tags/Actions
CLIPBOARD = ../Modules/Clipboard
MetisCore_FILES += $(CLIPBOARD)/Helper/MTSwipeUpGestureRecognizer.m \
	$(wildcard $(CLIPBOARD)/Shared/Tags/*.m) \
	$(wildcard $(CLIPBOARD)/Shared/Actions/*.m)
MetisCore_CFLAGS += -I$(CLIPBOARD)/Shared/Tags -I$(CLIPBOARD)/Shared/Actions -I../Preferences/ClipboardPages

MetisCore_FRAMEWORKS = Foundation CoreFoundation UIKit CoreGraphics QuartzCore ImageIO SafariServices PhotosUI UniformTypeIdentifiers JavaScriptCore
MetisCore_PRIVATE_FRAMEWORKS = AppSupport Preferences FrontBoardServices SpringBoardServices MobileCoreServices

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
MetisCore_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk
