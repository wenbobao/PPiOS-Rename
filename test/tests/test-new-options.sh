#Copyright 2016 PreEmptive Solutions, LLC
#See LICENSE.txt for licensing information

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


oneTimeSetUp() {
    checkForPPiOSRename
    checkOriginalIsClean

    rsyncInSandbox -a --delete "${original}/" "${prepared}"

    echo "Building ..."
    ( cd "${prepared}" ; make build &> "${buildLog}" )
    echo "Done."
}

oneTimeTearDown() {
    rmFromSandbox "${prepared}"
    rmFromSandbox "${work}"
}

setUp() {
    rsyncInSandbox -a --delete "${prepared}/" "${work}"

    targetApp="$(ls -td $(find "${work}/${buildDir}" -name "*.app") | head -1)"
    targetAppName="$(echo "${targetApp}" | sed 's,.*/\([^/]*\)\.app,\1,')"
    program="$(ls -td $(find "${targetApp}" -type f -and -name "${targetAppName}") | head -1)"

    pushd "${work}" > /dev/null
}

tearDown() {
    popd > /dev/null
}

checkVersion() {
    verify grep PreEmptive "${lastRun}"
    verify grep -i version "${lastRun}"
    verify grep 1.0.0 "${lastRun}"
}

checkUsage() {
    checkVersion # usage has version information

    verify grep "Usage:" "${lastRun}"
    # major modes
    verify grep -- --analyze "${lastRun}"
    verify grep -- --obfuscate-sources "${lastRun}"
    verify grep -- --translate-crashdump "${lastRun}"
    verify grep -- --translate-dsym "${lastRun}"
    verify grep -- --list-arches "${lastRun}"
    # minor modes
    verify grep -- --version "${lastRun}"
    verify grep -- --help "${lastRun}"
    # options
    verify grep -- --symbols-map "${lastRun}"
    verify grep -- -F "${lastRun}"
    verify grep -- -x "${lastRun}"
    verify grep -- --arch "${lastRun}"
    verify grep -- --sdk-root "${lastRun}"
    verify grep -- --sdk-ios "${lastRun}"
    verify grep -- --storyboards "${lastRun}"
    verify grep -- --symbols-header "${lastRun}"
}

checksumStoryboards() {
    ( cd $1 ; find . -name "*.storyboard" -exec md5 "{}" \; )
}

TEST "Baseline"
run ppios-rename --analyze "${program}"
verify test $? -eq 0
toList symbols.map list
verify grep '^methodA$' list
verify test -f symbols.map

TEST "Specifying just the .app works too"
run ppios-rename --analyze "${targetApp}"
verify test $? -eq 0
toList symbols.map list
verify grep '^methodA$' list
verify test -f symbols.map

TEST "Test usage"
run ppios-rename -h
verify test $? -eq 0
checkUsage
run ppios-rename --help
verify test $? -eq 0
checkUsage

TEST "Version works"
run ppios-rename --version
verify test $? -eq 0
checkVersion
verify test "$(cat "${lastRun}" | wc -l)" -le 3 # three or fewer lines

TEST "Option -i replaced with -x"
# try old option
run ppios-rename --analyze -i methodA "${program}"
verifyFails test $? -eq 0
# try new option
run ppios-rename --analyze -x methodA "${program}"
verify test $? -eq 0
toList symbols.map list
verifyFails grep '^methodA$' list

TEST "Option -m replaced with --symbols-map"
# try old option
run ppios-rename --analyze -m symbolz.map "${program}"
verifyFails test $? -eq 0
# try new option
verifyFails test -f symbolz.map
run ppios-rename --analyze --symbols-map symbolz.map "${program}"
verify test $? -eq 0
verify test -f symbolz.map

TEST "Option -O replaced with --symbols-header"
# try old option
run ppios-rename --analyze "${program}"
verify test $? -eq 0
run ppios-rename --obfuscate-sources -O symbolz.h
verifyFails test $? -eq 0
# try new option
run ppios-rename --obfuscate-sources --symbols-header symbolz.h
verify test $? -eq 0
verify test -f symbolz.h

TEST "Option --emit-excludes writes files"
run ppios-rename --analyze --emit-excludes excludes "${program}"
verify test $? -eq 0
verify test -f excludes-classFilters.list
verify test -f excludes-exclusionPatterns.list
verify test -f excludes-forbiddenNames.list

TEST "Change default map file from symbols.json to symbols.map"
verifyFails test -f symbols.json
verifyFails test -f symbols.map
run ppios-rename --analyze "${program}"
verify test $? -eq 0
verifyFails test -f symbols.json
verify test -f symbols.map

TEST "Option -X replaced with --storyboards"
run ppios-rename --analyze "${program}"
verify test $? -eq 0
originalStoryboards="${targetAppName}/Base.lproj"
originalSums="$(checksumStoryboards "${originalStoryboards}")"
copiedStoryboards="${targetAppName}/Copied.lproj"
cp -r "${originalStoryboards}" "${copiedStoryboards}"
verify test "${originalSums}" = "$(checksumStoryboards "${copiedStoryboards}")"
# try old option
run ppios-rename --obfuscate-sources -X "${copiedStoryboards}"
verifyFails test $? -eq 0
verify test "${originalSums}" = "$(checksumStoryboards "${originalStoryboards}")"
verify test "${originalSums}" = "$(checksumStoryboards "${copiedStoryboards}")"
# try new option
run ppios-rename --obfuscate-sources --storyboards "${copiedStoryboards}"
verify test $? -eq 0
verify test "${originalSums}" = "$(checksumStoryboards "${originalStoryboards}")"
verifyFails test "${originalSums}" = "$(checksumStoryboards "${copiedStoryboards}")"

assertHasInvalidOptionMessage() {
    verify grep 'invalid option' "${lastRun}" # short option form
}

assertHasUnrecognizedOptionMessage() {
    verify grep 'unrecognized option' "${lastRun}" # long option form
}

assertHasFirstArgumentMessage() {
    verify grep 'You must specify the mode of operation as the first argument' "${lastRun}"
}

assertAnalyzeInputFileMessage() {
    verify grep 'Input file must be specified for --analyze' "${lastRun}"
}

TEST "Error handling: no options"
run ppios-rename
assertSucceeds
assertRunsQuickly
checkUsage

TEST "Error handling: bad short option"
run ppios-rename -q
assertFails
assertRunsQuickly
assertHasInvalidOptionMessage
assertHasFirstArgumentMessage

TEST "Error handling: bad long option"
run ppios-rename --bad-long-option
assertFails
assertRunsQuickly
assertHasUnrecognizedOptionMessage
assertHasFirstArgumentMessage

TEST "Error handling: analyze: not enough arguments"
run ppios-rename --analyze
assertFails
assertRunsQuickly
assertAnalyzeInputFileMessage

TEST "Error handling: analyze: too many arguments"
run ppios-rename --analyze a b
assertFails
assertRunsQuickly

TEST "Error handling: analyze: bad short option"
run ppios-rename --analyze -q "${program}"
assertFails
assertRunsQuickly
assertHasInvalidOptionMessage

TEST "Error handling: analyze: bad long option"
run ppios-rename --analyze --bad-long-option "${program}"
assertFails
assertRunsQuickly
assertHasUnrecognizedOptionMessage

TEST "Error handling: analyze: options out of order"
run ppios-rename -F '!*' --analyze "${program}"
assertFails
assertRunsQuickly
assertHasFirstArgumentMessage

TEST "Error handling: analyze: check that app exists"
run ppios-rename --analyze "does not exist"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --symbols-map: argument missing"
run ppios-rename --analyze --symbols-map "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: --symbols-map: argument empty"
run ppios-rename --analyze --symbols-map '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: -F: argument missing"
run ppios-rename --analyze -F "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: -F: argument empty"
run ppios-rename --analyze -F '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: -F: argument malformed"
run ppios-rename --analyze -F '!' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: -x: argument missing"
run ppios-rename --analyze -x "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: -x: argument empty"
run ppios-rename --analyze -x '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --arch: argument missing"
run ppios-rename --analyze --arch "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: --arch: argument empty"
run ppios-rename --analyze --arch '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --arch: argument bogus"
run ppios-rename --analyze --arch pdp11 "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --sdk-root: argument missing"
run ppios-rename --analyze --sdk-root "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: --sdk-root: argument empty"
run ppios-rename --analyze --sdk-root '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --sdk-root: argument bogus"
run ppios-rename --analyze --sdk-root 'does not exist' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --sdk-ios: argument missing"
run ppios-rename --analyze --sdk-ios "${program}"
assertFails
assertRunsQuickly
# do not specify details of the output

TEST "Error handling: --analyze: --sdk-ios: argument empty"
run ppios-rename --analyze --sdk-ios '' "${program}"
assertFails
assertRunsQuickly

TEST "Error handling: --analyze: --sdk-ios: argument bogus"
run ppios-rename --analyze --sdk-ios bogus "${program}" # expecting: digits ( dot digits ) *
assertFails
assertRunsQuickly

report
