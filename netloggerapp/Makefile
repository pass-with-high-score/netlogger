ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NetLoggerApp

NetLoggerApp_FILES = main.m NLAppDelegate.m NLAppLogViewController.m NLAppLogDetailViewController.m NLLogEntry.m NLLogCell.m
NetLoggerApp_CFLAGS = -fobjc-arc
NetLoggerApp_FRAMEWORKS = UIKit Foundation WebKit
NetLoggerApp_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
