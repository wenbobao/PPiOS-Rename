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
    echo "$@" >> "${testLog}"
    "$@" 2>&1 | tee "${lastRun}" >> "${testLog}"
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


TEST "Baseline verifying project symbols are renamed"
run ppios-rename --analyze "${program}"
toList symbols.map list
#verify grep 'Ignoring @protocol __ARCLiteKeyedSubscripting__' "${lastRun}"
verify grep '^MoreTrimmable$' list
verify grep '^trimEvenMore$' list
for each in A B C D E F G I J # H is a protocol
do
    verify grep 'Adding @class BSClass'"${each}" "${lastRun}"
    verify grep '^BSClass'"${each}"'$' list
    verify grep '^method'"${each}"'$' list
    verify grep '^_squared'"${each}"'$' list
done
verifyFails grep '^[.]cxx_destruct$' list
verify grep 'Adding @category NSString+MoreTrimmable' "${lastRun}"
verify grep 'Ignoring @protocol NSObject' "${lastRun}"
verify grep 'Ignoring @protocol UIApplicationDelegate' "${lastRun}"

TEST "globbing negative filter"
run ppios-rename --analyze -F '!BS*' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassA' "${lastRun}"
verifyFails grep '^BSClassA$' list
verifyFails grep '^methodA$' list
verifyFails grep '^_squaredA$' list
verify grep 'Ignoring @class BSClassC' "${lastRun}"
verifyFails grep '^BSClassC$' list
verifyFails grep '^methodC$' list
verifyFails grep '^_squaredC$' list

TEST "globbing negative filter with positive filter"
run ppios-rename --analyze -F '!BS*' -F BSClassC "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassA' "${lastRun}"
verifyFails grep '^BSClassA$' list
verifyFails grep '^methodA$' list
verifyFails grep '^_squaredA$' list
verify grep 'Adding @class BSClassC' "${lastRun}"
verify grep '^BSClassC$' list
verify grep '^methodC$' list
verify grep '^_squaredC$' list

TEST "globbing negative filter with positive filter but -x wins"
run ppios-rename --analyze -F '!BS*' -F BSClassC -x BSClassC "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassA' "${lastRun}"
verifyFails grep '^BSClassA$' list
verifyFails grep '^methodA$' list
verifyFails grep '^_squaredA$' list
# Adding or Ignoring "BSClassC" in this case is misleading
verifyFails grep '^BSClassC$' list
verify grep '^methodC$' list
verify grep '^_squaredC$' list

TEST "positive filter before any negative filters produces warning"
run ppios-rename --analyze -F BSClassC -F '!BS*' "${program}"
verify grep "Warning: include filters without a preceding exclude filter have no effect" "${lastRun}"

TEST "-F works on categories"
run ppios-rename --analyze -F '!MoreTrimmable' "${program}"
verify grep 'Ignoring @category NSString+MoreTrimmable' "${lastRun}"
toList symbols.map list
verifyFails grep '^MoreTrimmable$' list
verifyFails grep '^trimEvenMore$' list

TEST "-F exclusion does not propagate by property type"
run ppios-rename --analyze -F '!BSClassA' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassA' "${lastRun}"
verifyFails grep '^BSClassA$' list
verifyFails grep '^methodA$' list
verifyFails grep '^_squaredA$' list
verify grep 'Adding @class BSClassB' "${lastRun}"
verify grep '^BSClassB$' list
verify grep '^methodB$' list
verify grep '^_squaredB$' list

TEST "-F exclusion does not propagate by method return type"
run ppios-rename --analyze -F '!BSClassC' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassC' "${lastRun}"
verifyFails grep '^BSClassC$' list
verifyFails grep '^methodC$' list
verifyFails grep '^_squaredC$' list
verify grep 'Adding @class BSClassD' "${lastRun}"
verify grep '^BSClassD$' list
verify grep '^methodD$' list
verify grep '^_squaredD$' list

TEST "-F exclusion does not propagate by method parameter type"
run ppios-rename --analyze -F '!BSClassE' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassE' "${lastRun}"
verifyFails grep '^BSClassE$' list
verifyFails grep '^methodE$' list
verifyFails grep '^_squaredE$' list
verify grep 'Adding @class BSClassF' "${lastRun}"
verify grep '^BSClassF$' list
verify grep '^methodF$' list
verify grep '^_squaredF$' list

TEST "-F exclusion does not propagate by protocol in property type"
run ppios-rename --analyze -F '!BSClassG' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassG' "${lastRun}"
verifyFails grep '^BSClassG$' list
verifyFails grep '^methodG$' list
verifyFails grep '^_squaredG$' list
verify grep 'Adding @protocol BSClassH' "${lastRun}"
verify grep '^BSClassH$' list

TEST "-F exclusion does not propagate by subclassing"
run ppios-rename --analyze -F '!BSClassI' "${program}"
toList symbols.map list
verify grep 'Ignoring @class BSClassI' "${lastRun}"
verifyFails grep '^BSClassI$' list
verifyFails grep '^methodI$' list
verifyFails grep '^_squaredI$' list
verify grep 'Adding @class BSClassJ' "${lastRun}"
verify grep '^BSClassJ$' list
verify grep '^methodJ$' list
verify grep '^_squaredJ$' list

TEST "Excluding a class with -x does not include its contents"
run ppios-rename --analyze -x BSClassA "${program}"
toList symbols.map list
verifyFails grep '^BSClassA$' list
verify grep '^methodA$' list
verify grep '^_squaredA$' list

TEST "Excluding a protocol with -x does not include its contents"
run ppios-rename --analyze -x BSClassH "${program}"
toList symbols.map list
verifyFails grep '^BSClassH$' list
verify grep '^methodH$' list

TEST "Excluding a property with -x removes all variants from symbols.map"
run ppios-rename --analyze "${program}"
toList symbols.map list
verify grep '^isSquaredA$' list
verify grep '^_squaredA$' list
verify grep '^setIsSquaredA$' list
verify grep '^_isSquaredA$' list
verify grep '^setSquaredA$' list
verify grep '^squaredA$' list
run ppios-rename --analyze -x squaredA --emit-excludes excludes "${program}"
toList symbols.map list
verifyFails grep '^isSquaredA$' list
verifyFails grep '^_squaredA$' list
verifyFails grep '^setIsSquaredA$' list
verifyFails grep '^_isSquaredA$' list
verifyFails grep '^setSquaredA$' list
verifyFails grep '^squaredA$' list

report
