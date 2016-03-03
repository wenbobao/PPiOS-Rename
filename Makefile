.PHONY: default
default: all

.PHONY: all
all: Pods ios-class-guard

Pods Podfile.lock: Podfile
	pod install

ios-class-guard: Pods
	xcodebuild \
		-workspace ios-class-guard.xcworkspace \
		-scheme ios-class-guard \
		-configuration Release \
		-derivedDataPath build \
		clean build test

.PHONY: clean
clean:
	$(RM) -r build Pods
