LIBRARY_NAME = MetisCore

# MetisCore 是包内私有共享库：所有注入目标与设置子包都以动态链接使用它，
# 保证同一 Objective-C 类在一个进程内只有一个镜像定义（03-architecture §1）。
# 载入准则：MT* 公共类型 + 被 SB/UIKit/设置子包共同引用的 DX* 共享类
# （含 vendored AltList，ADR-011 的 vendoring 备选路径：单一副本保证类唯一）。
MetisCore_INSTALL_PATH = /Library/Metis/Frameworks
MetisCore_LDFLAGS += -install_name /var/jb/Library/Metis/Frameworks/MetisCore.dylib

MetisCore_FILES = MTLog.m \
	MTPathResolver.m \
	MTProcessContext.m \
	MTModuleGate.m \
	MTConfigService.m

# Keyboard（TypeX）共享层：任一被两个以上镜像引用的 DX 类都在这里。
KEYBOARD = ../Modules/Keyboard/Sources
MetisCore_FILES += $(KEYBOARD)/DXGlobals.m \
	$(KEYBOARD)/DXAIEngine.m \
	$(KEYBOARD)/DXAIMarkdown.m \
	$(KEYBOARD)/DXAIPanel.m \
	$(KEYBOARD)/DXCell.m \
	$(KEYBOARD)/DXCollectionView.m \
	$(KEYBOARD)/DXDarwinOpenChannel.m \
	$(KEYBOARD)/DXFloatingAppInput.m \
	$(KEYBOARD)/DXFloatingAppRuntime.mm \
	$(KEYBOARD)/DXFloatingAppSession.m \
	$(KEYBOARD)/DXFloatingAppShelfChannel.m \
	$(KEYBOARD)/DXFloatingAppShelfState.m \
	$(KEYBOARD)/DXFloatingAppShelfView.m \
	$(KEYBOARD)/DXGlobalActionExecutor.m \
	$(KEYBOARD)/DXGlobalPanel.m \
	$(KEYBOARD)/DXHelper.m \
	$(KEYBOARD)/DXJavaScriptEngine.m \
	$(KEYBOARD)/DXJavaScriptHost.m \
	$(KEYBOARD)/DXKbdCollapseHandle.m \
	$(KEYBOARD)/DXKeyboardPanel.m \
	$(KEYBOARD)/DXPanelControlSession.m \
	$(KEYBOARD)/DXPanelPagedGridView.m \
	$(KEYBOARD)/DXPanelSystemControlsView.m \
	$(KEYBOARD)/DXAppLauncherCatalog.m \
	$(KEYBOARD)/DXAppSearch.m \
	$(KEYBOARD)/DXQuickLauncherView.m \
	$(KEYBOARD)/DXToolbarHorizontalGesture.m \
	$(KEYBOARD)/DXPrefsManager.m \
	$(KEYBOARD)/DXQuickActionProvider.m \
	$(KEYBOARD)/DXSensitiveURLExecutor.m \
	$(KEYBOARD)/DXShared.mm \
	$(KEYBOARD)/DXShortcutsGenerator.m \
	$(KEYBOARD)/DXSystemActionExecutor.m \
	$(KEYBOARD)/DXSystemOpenBroker.m \
	$(KEYBOARD)/DXSystemRecordingSession.m \
	$(KEYBOARD)/UIImage+Resize.m

# vendored AltList（MIT，来源见 Core/AltList/README-TypeX-vendor.md）
MetisCore_FILES += $(wildcard AltList/*.m)

MetisCore_CFLAGS = -fobjc-arc
MetisCore_CFLAGS += -Wno-tautological-pointer-compare
MetisCore_CFLAGS += -DMETIS_PACKAGE_VERSION=\"$(or $(PACKAGE_VERSION),$(THEOS_PACKAGE_BASE_VERSION))\"
MetisCore_CFLAGS += -I. -I$(KEYBOARD) -IAltList

# Clipboard（KayokoX）共享层：SwipeUp 识别器（SB+UIKit 共用）与 Shared Tags/Actions
CLIPBOARD = ../Modules/Clipboard
MetisCore_FILES += $(CLIPBOARD)/Helper/KayokoSwipeUpGestureRecognizer.m \
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
