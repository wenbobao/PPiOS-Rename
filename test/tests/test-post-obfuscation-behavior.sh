#!/bin/bash

#Copyright 2016 PreEmptive Solutions, LLC
#See LICENSE.txt for licensing information

targetAppName=BoxSim
thisDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
testRoot="$(dirname "${thisDirectory}")"
. "${testRoot}/tests/common.sh"


original="${apps}/${targetAppName}-support"
work="${sandbox}/${targetAppName}"
buildLog="${results}/build.log"
buildDir=build


oneTimeSetUp() {
    checkForPPiOSRename
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


assertSymbolicatedCrashdump() {
    verifyFails test grep -- '-\[BSClassP doSomethingP:]' "$1"
    verify grep -- '-\[BSClassO doSomethingO:]' "$1" # BSClassO was excluded from renaming
    verifyFails test grep -- '+\[BSClassN doSomethingInClassN:]' "$1"
    verifyFails test grep -- '-\[BSClassM doSomethingM:]' "$1"
    verifyFails test grep -- '-\[ViewController justGoAction:]' "$1"
}

assertDeobfuscatedCrashdump() {
    verify grep -- '-\[BSClassP doSomethingP:]' "$1"
    verify grep -- '-\[BSClassO doSomethingO:]' "$1"
    verify grep -- '+\[BSClassN doSomethingInClassN:]' "$1"
    verify grep -- '-\[BSClassM doSomethingM:]' "$1"
    verify grep -- '-\[ViewController justGoAction:]' "$1"
}

input=symbolicated.crash
output=de-obfuscated.crash

TEST "translate crashdump works"
originalSum="$(checksum "${input}")"
run "${PPIOS_RENAME}" --translate-crashdump "${input}" "${output}"
assertSucceeds
verify test "${originalSum}" = "$(checksum "${input}")" # no change to original
verify test -f "${output}"
assertSymbolicatedCrashdump "${input}"
assertDeobfuscatedCrashdump "${output}"

TEST "translate crashdump: error handling: symbols-map works"
mv symbols.map symbolz.map
run "${PPIOS_RENAME}" --translate-crashdump "${input}" "${output}"
assertFails
assertRunsQuickly
run "${PPIOS_RENAME}" --translate-crashdump --symbols-map symbolz.map "${input}" "${output}"
assertSucceeds
verify test "${originalSum}" = "$(checksum "${input}")" # no change to original
verify test -f "${output}"
assertSymbolicatedCrashdump "${input}"
assertDeobfuscatedCrashdump "${output}"

TEST "translate crashdump overwriting original works"
originalSum="$(checksum "${input}")"
run "${PPIOS_RENAME}" --translate-crashdump "${input}" "${input}"
assertSucceeds
verifyFails test "${originalSum}" = "$(checksum "${input}")" # original overwritten
assertDeobfuscatedCrashdump "${input}"

TEST "translate crashdump: error handling: no arguments"
run "${PPIOS_RENAME}" --translate-crashdump
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: only one argument"
run "${PPIOS_RENAME}" --translate-crashdump "${input}"
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: too many arguments"
run "${PPIOS_RENAME}" --translate-crashdump "${input}" "${output}" bogus
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: empty input"
run "${PPIOS_RENAME}" --translate-crashdump '' "${output}"
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: bogus input"
run "${PPIOS_RENAME}" --translate-crashdump bogus "${output}"
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: empty output"
run "${PPIOS_RENAME}" --translate-crashdump "${input}" ''
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: symbols-map argument missing"
run "${PPIOS_RENAME}" --translate-crashdump --symbols-map "${input}" "${output}"
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: symbols-map argument empty"
run "${PPIOS_RENAME}" --translate-crashdump --symbols-map '' "${input}" "${output}"
assertFails
assertRunsQuickly

TEST "translate crashdump: error handling: symbols-map argument bogus"
run "${PPIOS_RENAME}" --translate-crashdump --symbols-map bogus "${input}" "${output}"
assertFails
assertRunsQuickly

symbolicateCrash() {
    if test $# -ne 4
    then
        echo "$(basename $0): usage: symbolicateCrash <app-name> <dSYM-binary> <in> <out>" >&2
        exit 1
    fi

    addresses="$(cat "$3" \
        | sed -n '/^Thread 0 Crashed:$/,/^$/p' \
        | grep "$1" \
        | awk '{ print $4, $3 }')"
    verify test "$(echo "${addresses}" | wc -l)" -ge 2

    echo -n "" > "$4"
    echo "${addresses}" | while read line
    do
        base="$(echo "${line}" | awk '{print $1}')"
        address="$(echo "${line}" | awk '{print $2}')"
        xcrun atos -o "$2" -arch armv7 -l "${base}" "${address}" >> "$4"
    done
}

crash=unsymbolicated.crash
deobfuscated=de-obfuscated-partial.crash
input=BoxSim.app.dSYM
output=de-obfuscated.dSYM
outputBinary="${output}/Contents/Resources/DWARF/BoxSim"

TEST "translate dSYM works"
originalSum="$(checksum "${input}")"
run "${PPIOS_RENAME}" --translate-dsym "${input}" "${output}"
assertSucceeds
verify test "${originalSum}" = "$(checksum "${input}")" # no change to original
verify test -e "${output}"
verifyFails test "${originalSum}" = "$(checksum "${output}")" # changed
symbolicateCrash "${targetAppName}" "${outputBinary}" "${crash}" "${deobfuscated}"
assertDeobfuscatedCrashdump "${deobfuscated}"

TEST "translate dSYM works: error handling: no arguments"
run "${PPIOS_RENAME}" --translate-dsym
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: only one argument"
run "${PPIOS_RENAME}" --translate-dsym "${input}"
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: too many arguments"
run "${PPIOS_RENAME}" --translate-dsym "${input}" "${output}" bogus
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: too many arguments"
run "${PPIOS_RENAME}" --translate-dsym "${input}" "${output}" bogus
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: empty input"
run "${PPIOS_RENAME}" --translate-dsym '' "${output}"
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: bogus input"
run "${PPIOS_RENAME}" --translate-dsym bogus "${output}"
assertFails
assertRunsQuickly

TEST "translate dSYM works: error handling: empty output"
run "${PPIOS_RENAME}" --translate-dsym "${input}" ''
assertFails
assertRunsQuickly

TEST "translate dsym: error handling: symbols-map argument missing"
run "${PPIOS_RENAME}" --translate-dsym --symbols-map "${input}" "${output}"
assertFails
assertRunsQuickly

TEST "translate dsym: error handling: symbols-map argument empty"
run "${PPIOS_RENAME}" --translate-dsym --symbols-map '' "${input}" "${output}"
assertFails
assertRunsQuickly

TEST "translate dsym: error handling: symbols-map argument bogus"
run "${PPIOS_RENAME}" --translate-dsym --symbols-map bogus "${input}" "${output}"
assertFails
assertRunsQuickly

report
