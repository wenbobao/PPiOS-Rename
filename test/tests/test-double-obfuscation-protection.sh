#!/bin/bash

targetAppName=BoxSim
thisDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
testRoot="$(dirname "${thisDirectory}")"
. "${testRoot}/tests/common.sh"


original="${apps}/${targetAppName}"
work="${sandbox}/${targetAppName}"
buildLog="${results}/build.log"
buildDir=build

oneTimeSetUp() {
    checkOriginalIsClean
}

oneTimeTearDown() {
    rmFromSandbox "${work}"
}

setUp() {
    rsyncInSandbox -a --delete "${original}/" "${work}"
    pushd "${work}" > /dev/null
}

tearDown() {
    popd > /dev/null
}


program="${work}/build/Build/Products/Release-iphoneos/${targetAppName}.app/${targetAppName}"

TEST "Normal obfuscated build"
run make build
run ppios-rename --analyze "${program}"
run ppios-rename --obfuscate-sources
run make build
nmLog="${work}/nm.log"
nm "${program}" > "${nmLog}"
verifyFails grep BSClass "${nmLog}"

TEST "Analyzing obfuscated build fails with error (BAOBA)"
run make build
run ppios-rename --analyze "${program}"
run ppios-rename --obfuscate-sources
run make build
run ppios-rename --analyze "${program}"
verify test $? -ne 0
verify grep "Error: Analyzing an already obfuscated binary. This will result in an unobfuscated binary. Please see the documentation for details." "${lastRun}"

TEST "Analyzing obfuscated build fails with error (BAOBA), even with few symbols"
run make build
run ppios-rename --analyze -F '!*' -F BSClassB -x BSClassB -x squaredB "${program}"
run ppios-rename --obfuscate-sources
run make build
run ppios-rename --analyze -F '!*' -F BSClassB -x BSClassB -x squaredB "${program}"
verify test $? -ne 0
verify grep "Error: Analyzing an already obfuscated binary. This will result in an unobfuscated binary. Please see the documentation for details." "${lastRun}"

TEST "Building double-obfuscated sources yields failing build (BAOAOB)"
verifyFails test -e "${buildDir}"
run make build
run ppios-rename --analyze "${program}"
run ppios-rename --obfuscate-sources
run ppios-rename --analyze "${program}"
run ppios-rename --obfuscate-sources
run make build
verify test $? -ne 0
verify grep "Double obfuscation detected. This will result in an unobfuscated binary. Please see the documentation for details." "${lastRun}"

report
