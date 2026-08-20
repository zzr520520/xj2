# 现代越狱标准架构 (Rootless: Dopamine/Palera1n)
export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeDeviceHook
FakeDeviceHook_FILES = FakeDeviceTweak/Tweak.x FakeDeviceTweak/NetworkSpoof.x
FakeDeviceHook_FRAMEWORKS = UIKit IOKit CoreLocation CoreTelephony StoreKit SystemConfiguration AdSupport
FakeDeviceHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new

include $(THEOS_MAKE_PATH)/tweak.mk