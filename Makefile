# Copyright 2016 PreEmptive Solutions, LLC
DIST_DIR=PPiOS-ClassGuard-v1.0.0
BUILD_DIR=build
PROGRAM_NAME=ios-class-guard

PROGRAM=$(BUILD_DIR)/Build/Products/Release/$(PROGRAM_NAME)
GIT_CMD=git rev-parse --short HEAD
GIT_HASH_CHECK=$(GIT_CMD) &> /dev/null
GIT_HASH=$(shell $(GIT_HASH_CHECK) && $(GIT_CMD) | sed 's,^,-,')
BUILD_NUMBER_CHECK=! test -z "$${BUILD_NUMBER}"
BUILD_NUMBER=$(shell $(BUILD_NUMBER_CHECK) && echo $${BUILD_NUMBER} | sed 's,^,-,')
DIST_PACKAGE=$(DIST_DIR)$(GIT_HASH)$(BUILD_NUMBER).tgz

.PHONY: default
default: all

.PHONY: all
all: Pods $(PROGRAM)

.PHONY: dist
dist: $(DIST_PACKAGE)

Pods Podfile.lock: Podfile
	pod install

$(PROGRAM): Pods
	xctool \
		-workspace ios-class-guard.xcworkspace \
		-scheme ios-class-guard \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		-reporter plain \
		-reporter junit:$(BUILD_DIR)/unit-test-report.xml \
		clean build test

$(DIST_PACKAGE): package-check distclean $(PROGRAM)
	mkdir -p $(DIST_DIR)
	cp $(PROGRAM) \
		README.md \
		LICENSE.txt \
		ThirdPartyLicenses.txt \
		CHANGELOG.md \
		$(DIST_DIR)
	tar -cvpzf $@ --options gzip:compression-level=9 $(DIST_DIR)

.PHONY: package-check
package-check:
	@$(GIT_HASH_CHECK) || echo "Info: git hash unavailable, omitting from package name"
	@$(BUILD_NUMBER_CHECK) || echo "Info: BUILD_NUMBER unset, omitting from package name"

.PHONY: clean
clean:
	$(RM) -r build Pods

.PHONY: distclean
distclean: clean
	$(RM) -r $(DIST_DIR) $(DIST_DIR)*.tgz
