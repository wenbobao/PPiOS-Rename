#!/bin/bash

testRoot="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
sandbox="${testRoot}/sandbox"
apps="${testRoot}/apps"
results="${testRoot}/results"

#echo "testRoot=${testRoot}"
#echo "sandbox=${sandbox}"
#echo "apps=${apps}"

test -e "${sandbox}" || mkdir -p "${sandbox}"
test -e "${results}" || mkdir -p "${results}"

targetName=BoxSim

original="${apps}/${targetName}"
work="${sandbox}/${targetName}"
lastRun="${results}/run.log"
buildLog="${results}/build.log"
testLog="${results}/test-suite.log"
buildDir=build

testCount=0
failureCount=0
errorCount=0
successCount=0

testName=""
error=""
firstSetup=yes

TEST() {
    if test "${firstSetup}" = "yes"
    then
        firstSetup=""
        date > "${testLog}"
    else
        tearDown # between tests
    fi

    testName="$1"
    testCount=$((testCount + 1))


    echo "Setup:" >> "${testLog}"
    rsync -a --delete "${original}/" "${work}"

    cd "${work}"


    echo -n "Test: ${testName}: "
    echo "Test: ${testName}: " >> "${testLog}"
}

tearDown() {
    if test "${testName}" != ""
    then
        if test "${error}" != ""
        then
            echo "FAIL"
            echo "error: ${error}"
            failureCount=$((failureCount + 1))
        else
            echo "PASS"
            successCount=$((successCount + 1))
        fi

        testName=""
        error=""
    fi
}

report() {
    tearDown

    echo "Done."
    echo "Tests run: ${testCount}, pass: ${successCount}, fail: ${failureCount}"

    if test "${testCount}" -eq 0
    then
        echo "error: no tests were executed" >&2
        exit 2
    fi

    if test "${successCount}" -lt "${testCount}" \
            || test "${failureCount}" -gt 0
    then
        exit 1
    fi
}

run() {
    echo "$@" >> "${testLog}"
    "$@" 2>&1 | tee "${lastRun}" >> "${testLog}"
    return "${PIPESTATUS[0]}"
}

verify() {
    echo "verify $@" >> "${testLog}"
    if test "${error}" = ""
    then
        "$@" &> /dev/null
        result=$?
        if test "${result}" -ne 0
        then
            error="\"$@\" (return: ${result})"
        fi
    fi
}

verifyFails() {
    echo "verifyFails $@" >> "${testLog}"
    if test "${error}" = ""
    then
        "$@" &> /dev/null
        result=$?
        if test "${result}" -eq 0
        then
            error="\"$@\" (expected non-zero)"
        fi
    fi
}

toList() {
    if test $# -lt 2
    then
        echo "$(basename $0): toList <symbols.map> <original-symbols.list>" >&2
        exit 1
    fi

    source="$1"
    destination="$2"

    echo "Writing ${destination}" >> "${testLog}"
    cat "${source}" | sed 's|[",]||g' | awk '{ print $3; }' | sort | grep -v '^$' > "${destination}"
}

program="${work}/build/Build/Products/Release-iphoneos/${targetName}.app/${targetName}"

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
