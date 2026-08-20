export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FakeDeviceHook
FakeDeviceHook_FILES = FakeDeviceTweak/Tweak.x FakeDeviceTweak/NetworkSpoof.x
FakeDeviceHook_FRAMEWORKS = UIKit IOKit CoreLocation CoreTelephony Metal StoreKit WebKit
FakeDeviceHook_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk