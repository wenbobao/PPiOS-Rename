#!/usr/bin/env false
# this script is intended to be sourced by other scripts, not run directly

if test "${testRoot}" = "" \
        || test "${targetAppName}" = ""
then
    echo "common.sh: error: set targetAppName and testRoot variable to the root of the" >&2
    echo "test directory before sourcing this script.  For example:" >&2
    echo "" >&2
    echo '  targetAppName=BoxSim' >&2
    echo '  thisDirectory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' >&2
    echo '  testRoot="$(dirname "${thisDirectory}")"' >&2
    echo '  . "${testRoot}/tests/common.sh"' >&2
    exit 1
fi

sandbox="${testRoot}/sandbox"
apps="${testRoot}/apps"
results="${testRoot}/results"

test -e "${sandbox}" || mkdir -p "${sandbox}"
test -e "${results}" || mkdir -p "${results}"

lastRun="${results}/last.log"
lastResultFile="${results}/last.result"
testLog="${results}/test-suite.log"

shortTimeout=100 # milliseconds

testCount=0
failureCount=0
successCount=0

testName=""
error=""
firstSetup=yes

# capitalization of these methods mimics that of shunit2
oneTimeSetUp() {
    return 0
}

oneTimeTearDown() {
    return 0
}

setUp() {
    return 0
}

tearDown() {
    return 0
}

finishTest() {
    if test "${testName}" != ""
    then
        tearDown

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

TEST() {
    if test "${firstSetup}" = "yes"
    then
        firstSetup=""
        date > "${testLog}"

        oneTimeSetUp
    else
        # between tests
        finishTest
    fi

    testName="$1"
    testCount=$((testCount + 1))

    echo "Setup:" >> "${testLog}"

    setUp

    echo -n "Test: ${testName}: "
    echo "Test: ${testName}: " >> "${testLog}"
}

report() {
    finishTest

    oneTimeTearDown

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

        # time the execution, get the exit code, and record stdout and stderr
        # subshell is necessary to get at the output
        # the awk-bc part splits the output from time and produces a millisecond value
        lastMS=$( (
            time "$@" &> "${lastRun}"
            echo $? > "${lastResultFile}"
        ) 2>&1 \
            | grep real \
            | awk 'BEGIN { FS="[\tms.]" } { printf("(%d * 60 + %d) * 1000 + %d\n", $2, $3, $4); }' \
            | bc)

        lastResult="$(cat "${lastResultFile}")"

        cat "${lastRun}" >> "${testLog}"
        echo "exit code: ${lastResult}" >> "${testLog}"
        echo "run time: ${lastMS} ms" >> "${testLog}"

        # because of the subshell, the result cannot be passed directly in a variable
        return "${lastResult}"
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
    if test "${error}" = ""
    then
        if test $# -lt 2
        then
            echo "$(basename $0): toList <symbols.map> <original-symbols.list>" >&2
            exit 1
        fi

        source="$1"
        destination="$2"

        echo "Writing ${destination}" >> "${testLog}"
        cat "${source}" | sed 's|[",]||g' | awk '{ print $3; }' | sort | grep -v '^$' > "${destination}"
    fi
}

rsyncInSandbox() {
    if test $# -lt 2
    then
        echo "$(basename $0): rsyncInSandbox [options] <source-spec> <destination>" >&2
        echo "  Review help documentation for rsync." >&2
        exit 1
    fi

    if [[ "${@: -1}" != */sandbox/* ]]
    then
        echo "$(basename $0): rsyncInSandbox: destination must contain 'sandbox' path part" >&2
        echo "  destination: ${@: -1}" >&2
        exit 2
    fi

    rsync "$@"
}

rmFromSandbox() {
    if test $# -ne 1
    then
        echo "$(basename $0): rmFromSandbox <directory>" >&2
        echo "  Only supports removing one directory at a time from the sandbox." >&2
        exit 1
    fi

    if [[ "$1" != */sandbox/* ]]
    then
        echo "$(basename $0): rmFromSandbox: directory must contain 'sandbox' path part" >&2
        echo "  directory: $1" >&2
        exit 2
    fi

    rm -r -- "$1"
}

checkOriginalIsClean() {
    if test "${original}" != "" \
       && test "${buildDir}" != "" \
       && test -e "${original}/${buildDir}"
    then
        echo "Original directory is not clean: ${original}/${buildDir}" >&2
        exit 1
    fi
}

checkForPPiOSRename() {
    type ppios-rename &> /dev/null
    if test $? -ne 0
    then
        echo "$(basename $0): cannot find ppios-rename in PATH" >&2
        exit 1
    fi
}

assertSucceeds() {
    verify test $? -eq 0
}

assertFails() {
    verify test $? -ne 0
}

assertRunsQuickly() {
    verify test "${lastMS}" -lt "${shortTimeout}"
}
