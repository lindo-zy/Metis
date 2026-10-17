BUNDLE_NAME = MetisPrefs

# 统一设置壳：系统设置里唯一的 Metis 入口（docs/development/02/03）。
# 首页五分类（全局/键盘/剪切板/截图/其他）直达实际配置；全局与其他分类页
# 在壳内实现，键盘/剪切板/截图经 MTPrefsSubbundleLoader 复用子包控制器。
MetisPrefs_FILES = MTPrefsRootController.m \
	MTPrefsSubbundleLoader.m \
	MTPrefsGlobalController.m \
	MTPrefsBindingsController.m \
	MTPrefsReferencesController.m \
	MTPrefsOtherController.m \
	MTPrefsAboutController.m

MetisPrefs_CFLAGS = -fobjc-arc
MetisPrefs_CFLAGS += -I../../Core -I../../Core/SharedResources
MetisPrefs_LDFLAGS += $(THEOS_OBJ_DIR)/MetisCore.dylib
MetisPrefs_INSTALL_PATH = /Library/PreferenceBundles
MetisPrefs_FRAMEWORKS = UIKit CoreGraphics
MetisPrefs_PRIVATE_FRAMEWORKS = Preferences AppSupport

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Metis.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Metis.plist$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/Metis.png $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Metis.png$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/Metis@2x.png $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Metis@2x.png$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/Metis@3x.png $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Metis@3x.png$(ECHO_END)
	$(ECHO_NOTHING)test -n "$(PACKAGE_VERSION)" || { echo "error: PACKAGE_VERSION not set (use build.sh)" >&2; exit 1; }$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleShortVersionString -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)plutil -replace CFBundleVersion -string "$(PACKAGE_VERSION)" "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/MetisPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/usr/share/doc/com.lindo.metis$(ECHO_END)
	$(ECHO_NOTHING)cp ../../LICENSE-NOTICE "$(THEOS_STAGING_DIR)/usr/share/doc/com.lindo.metis/LICENSE-NOTICE"$(ECHO_END)
	$(ECHO_NOTHING)cp ../../LICENSE "$(THEOS_STAGING_DIR)/usr/share/doc/com.lindo.metis/LICENSE"$(ECHO_END)
