# Copyright 2016 PreEmptive Solutions, LLC
PROJECT_NAME=PPiOS-ClassGuard
VERSION=v1.0.0
PROGRAM_NAME=ios-class-guard

BUILD_DIR=build
PROGRAM=$(BUILD_DIR)/Build/Products/Release/$(PROGRAM_NAME)
GIT_CMD=git rev-parse --short HEAD
GIT_HASH_CHECK=$(GIT_CMD) &> /dev/null
GIT_HASH=$(shell $(GIT_HASH_CHECK) && $(GIT_CMD) | sed 's,^,-,')
BUILD_NUMBER_CHECK=! test -z "$${BUILD_NUMBER}"
BUILD_NUMBER=$(shell $(BUILD_NUMBER_CHECK) && echo $${BUILD_NUMBER} | sed 's,^,-,')
DIST_DIR=$(PROJECT_NAME)-$(VERSION)
FULL_VERSION=$(VERSION)$(GIT_HASH)$(BUILD_NUMBER)
ARCHIVE_DIR=$(FULL_VERSION)
DIST_PACKAGE=$(ARCHIVE_DIR)/$(PROJECT_NAME)-$(FULL_VERSION).tgz

XCODEBUILD_OPTIONS=\
	-workspace ios-class-guard.xcworkspace \
	-scheme ios-class-guard \
	-configuration Release \
	-derivedDataPath $(BUILD_DIR) \
	-reporter plain \
	-reporter junit:$(BUILD_DIR)/unit-test-report.xml

.PHONY: default
default: all

.PHONY: all
all: Pods $(PROGRAM)

# convenience target
.PHONY: it
it: clean all check

Pods Podfile.lock: Podfile
	pod install

$(PROGRAM): Pods
	xctool $(XCODEBUILD_OPTIONS) build

.PHONY: check
check: $(PROGRAM)
	xctool $(XCODEBUILD_OPTIONS) test

.PHONY: archive
archive: package-check distclean archive-dir $(PROGRAM) check $(DIST_PACKAGE)
	cp -r $(PROGRAM).dSYM $(ARCHIVE_DIR)/

.PHONY: package-check
package-check:
	@$(GIT_HASH_CHECK) || echo "Info: git hash unavailable, omitting from package name"
	@$(BUILD_NUMBER_CHECK) || echo "Info: BUILD_NUMBER unset, omitting from package name"

.PHONY: archive-dir
archive-dir:
	mkdir -p $(ARCHIVE_DIR)

$(DIST_PACKAGE): $(PROGRAM)
	mkdir -p $(DIST_DIR)
	cp $(PROGRAM) \
		README.md \
		LICENSE.txt \
		ThirdPartyLicenses.txt \
		CHANGELOG.md \
		$(DIST_DIR)
	tar -cvpzf $@ --options gzip:compression-level=9 $(DIST_DIR)

.PHONY: clean
clean:
	$(RM) -r $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	$(RM) -r Pods $(DIST_DIR)* $(VERSION)*
