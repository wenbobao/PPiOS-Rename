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

original="${apps}/BoxSim"
work="${sandbox}/BoxSim"
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
        rsync -a --delete "${original}/" "${work}"
    else
        tearDown # between tests
    fi

    testName="$1"
    testCount=$((testCount + 1))


    echo "Setup:" >> "${testLog}"
    rsync -a --delete --exclude=build "${original}/" "${work}"

    cd "${work}"

    if ! test -e "${buildDir}"
    then
        echo "Building ..."
        make build &> "${buildLog}"
        echo "Done."
    fi

    targetApp="$(ls -td $(find "${work}/${buildDir}" -name "*.app") | head -1)"
    targetAppName="$(echo "${targetApp}" | sed 's,.*/\([^/]*\)\.app,\1,')"
    program="$(ls -td $(find "${targetApp}" -type f -and -name "${targetAppName}") | head -1)"

    #echo "targetApp=${targetApp}"
    #echo "targetAppName=${targetAppName}"
    #echo "program=${program}"

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
    if test "${error}" = ""
    then
        echo "$@" >> "${testLog}"
        "$@" 2>&1 | tee "${lastRun}" >> "${testLog}"
        return ${PIPESTATUS[0]}
    else
        return 0
    fi
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

checkUsage() {
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

TEST "Test usage"
run ppios-rename
verify test $? -eq 0
checkUsage
run ppios-rename -h
verify test $? -eq 0
checkUsage
run ppios-rename --help
verify test $? -eq 0
checkUsage

TEST "Version works"
run ppios-rename --version
verify test $? -eq 0
verify grep PreEmptive "${lastRun}"
linesInOutput=$(cat "${lastRun}" | wc | awk '{ print $1 }')
verify test $linesInOutput -le 3

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
originalStoryboards=BoxSim/Base.lproj
originalSums="$(checksumStoryboards "${originalStoryboards}")"
copiedStoryboards=BoxSim/Copied.lproj
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

report
