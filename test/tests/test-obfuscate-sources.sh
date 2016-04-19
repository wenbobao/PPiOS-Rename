#!/bin/bash

targetAppName=BoxSim
thisDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
testRoot="$(dirname "${thisDirectory}")"
. "${testRoot}/tests/common.sh"


original="${apps}/${targetAppName}"
prepared="${sandbox}/${targetAppName}-pre"
work="${sandbox}/${targetAppName}"
buildLog="${results}/build.log"
buildDir=build

program="${work}/${appInFolder}"


oneTimeSetUp() {
    checkForPPiOSRename
    checkOriginalIsClean

    rsyncInSandbox -a --delete "${original}/" "${prepared}"

    echo "Building and analyzing ..."
    (
        set -e
        cd "${prepared}"
        make build &> "${buildLog}"
        productsDir="${prepared}/${buildDir}/Build/Products"
        preparedProgram="${productsDir}/Release-iphoneos/${targetAppName}.app/${targetAppName}"
        ppios-rename --analyze "${preparedProgram}" >> "${buildLog}" 2>&1
    )
    if test $? -ne 0
    then
        echo "Setup failed" >&2
        exit 1
    fi
    
    echo "Done."
}

oneTimeTearDown() {
    rmFromSandbox "${prepared}"
#    rmFromSandbox "${work}"
}

setUp() {
    rsyncInSandbox -a --delete "${prepared}/" "${work}"
    pushd "${work}" > /dev/null
}

tearDown() {
    popd > /dev/null
}


checksumStoryboards() {
    ( cd $1 ; find . -name "*.storyboard" -exec md5 "{}" \; )
}



TEST "Obfuscate works"
run ppios-rename --obfuscate-sources
assertSucceeds

TEST "obfuscate sources: option --symbols-header: works"
verifyFails test -f symbolz.h
run ppios-rename --obfuscate-sources --symbols-header symbolz.h
assertSucceeds
verify test -f symbolz.h

TEST "obfuscate sources: option --symbols-header: missing argument fails"
run ppios-rename --obfuscate-sources --symbols-header
assertFails
assertRunsQuickly

TEST "obfuscate sources: option --symbols-header: empty argument fails"
run ppios-rename --obfuscate-sources --symbols-header ''
assertFails
assertRunsQuickly

TEST "obfuscate sources: option --storyboards: works"
originalStoryboards="${targetAppName}/Base.lproj"
originalSums="$(checksumStoryboards "${originalStoryboards}")"
copiedStoryboards="${targetAppName}/Copied.lproj"
run cp -r "${originalStoryboards}" "${copiedStoryboards}"
verify test "${originalSums}" = "$(checksumStoryboards "${copiedStoryboards}")"
run ppios-rename --obfuscate-sources --storyboards "${copiedStoryboards}"
assertSucceeds
verify test "${originalSums}" = "$(checksumStoryboards "${originalStoryboards}")"
verifyFails test "${originalSums}" = "$(checksumStoryboards "${copiedStoryboards}")"

TEST "obfuscate sources: option --storyboards: missing argument fails"
run ppios-rename --obfuscate-sources --storyboards
assertFails
assertRunsQuickly

TEST "obfuscate sources: option --storyboards: empty argument fails"
run ppios-rename --obfuscate-sources --storyboards ''
assertFails
assertRunsQuickly

TEST "obfuscate sources: option --storyboards: bogus"
run ppios-rename --obfuscate-sources --storyboards bogus
assertFails
assertRunsQuickly

report
