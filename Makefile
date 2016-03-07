# Copyright 2016 PreEmptive Solutions, LLC
DISTDIR=PPiOS-CG-v1.0.0

.PHONY: default
default: all

.PHONY: all
all: Pods ios-class-guard

Pods Podfile.lock: Podfile
	pod install

ios-class-guard: Pods
	xctool \
		-workspace ios-class-guard.xcworkspace \
		-scheme ios-class-guard \
		-configuration Release \
		-derivedDataPath build \
		-reporter plain \
		-reporter junit:build/unit-test-report.xml \
		clean build test

.PHONY: dist
dist: ios-class-guard
	$(MKDIR) $(DISTDIR)

.PHONY: clean
clean:
	$(RM) -r build Pods
