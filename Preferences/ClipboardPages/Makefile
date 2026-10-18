BUNDLE_NAME = MetisClipboardPrefs

# Clipboard（MetisClipboard）详细设置子包：从统一设置壳的模块页进入。
# 共享层（Tags/Actions/AltList）链接 MetisCore；不再注册独立
# PreferenceLoader 入口（layout/ 旧入口不安装）。
MetisClipboardPrefs_FILES = $(wildcard Controllers/*.m) \
	$(wildcard Cells/*.m) \
	$(wildcard Utilities/*.m) \
	$(wildcard Models/*.m)

MetisClipboardPrefs_CFLAGS = -fobjc-arc
MetisClipboardPrefs_CFLAGS += -I. -IControllers -ICells -IUtilities -IModels
MetisClipboardPrefs_CFLAGS += -I../../Modules/Clipboard/Shared/Tags -I../../Modules/Clipboard/Shared/Actions
MetisClipboardPrefs_CFLAGS += -I../../Core -I../../Core/SharedResources -I../../Modules/Keyboard/Sources
MetisClipboardPrefs_INSTALL_PATH = /Library/PreferenceBundles
MetisClipboardPrefs_FRAMEWORKS = CoreGraphics QuartzCore Security UIKit
MetisClipboardPrefs_PRIVATE_FRAMEWORKS = FrontBoardServices Preferences SpringBoardServices
MetisClipboardPrefs_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisClipboardPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisClipboardPrefs.bundle/Info.plist"$(ECHO_END)
