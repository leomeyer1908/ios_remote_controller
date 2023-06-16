ARCHS = arm64
SDKVERSION=11.4

TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = SpringBoard


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ios_remote_controller

customtouch_FILES = Tweak.x
customtouch_CFLAGS = -fobjc-arc
customtouch_FRAMEWORKS = UIKit

customtouch_PRIVATE_FRAMEWORKS = IOKit
customtouch_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
