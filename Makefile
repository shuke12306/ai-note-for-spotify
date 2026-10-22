THEOS ?= $(HOME)/theos
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
DEBUG := 0
FINALPACKAGE := 1
PACKAGE_VERSION := 1.1.0
LOGOS_DEFAULT_GENERATOR := internal

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AINote
AINote_FILES := Sources/Tweak.x Sources/SpotifyHooks.x Sources/CGDTrackReader.m Sources/CGDAdapter.m Sources/CGDDiagnostics.m Sources/CGDPageProbe.m Sources/CGDGuideUI.m Sources/CGDSettingsStore.m Sources/CGDModulePreferences.m Sources/CGDPlaybackTheme.m Sources/CGDGuideData.m Sources/CGDGuideCache.m Sources/CGDGuideService.m Sources/CGDGuideLanguage.m
AINote_FRAMEWORKS := UIKit Foundation QuartzCore Security
AINote_FILES += Sources/CGDLocalization.m Sources/CGDGuidePrompts.m Sources/CGDGuideModuleCache.m Sources/CGDGuideLibrary.m
AINote_CFLAGS := -fobjc-arc -Wall -Wextra -Werror
AINote_LDFLAGS := -Wl,-install_name,@rpath/AINote.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
