BUNDLE_NAME = MetisPrefs

# 统一设置壳：系统设置里唯一的 Metis 入口（03-architecture §1）。
# 只链接 MetisCore 与 Preferences 私有框架；不加载完整业务目标。
MetisPrefs_FILES = MTPrefsRootController.m \
	MTPrefsModuleController.m \
	MTPrefsAboutController.m

MetisPrefs_CFLAGS = -fobjc-arc
MetisPrefs_CFLAGS += -I../../Core
MetisPrefs_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib
MetisPrefs_INSTALL_PATH = /Library/PreferenceBundles
MetisPrefs_FRAMEWORKS = UIKit CoreGraphics
MetisPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Metis.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Metis.plist$(ECHO_END)
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/usr/share/doc/com.lindo.metis$(ECHO_END)
	$(ECHO_NOTHING)cp LICENSE-NOTICE "$(THEOS_STAGING_DIR)/usr/share/doc/com.lindo.metis/LICENSE-NOTICE" 2>/dev/null || true$(ECHO_END)
