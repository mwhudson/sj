#!/bin/bash

set -eu

usage () {
    echo "usage: sj [options] JOB_FILE [PARAM=VALUE ...]"
    echo ""
    echo "Submit a job to LAVA."
    echo ""
    echo "If JOB_FILE ends with .yaml or .yml it is converted from YAML to JSON."
    echo ""
    echo "JOB_FILE can be followed multiple PARAM=VALUE specifications -- if any"
    echo "lava_test_shell actions specify a value for PARAM it will be overwritten"
    echo "with VALUE before submission."
    echo ""
    echo "Optional arguments:"
    echo " --show-job     Show the job after conversion to JSON and substituting"
    echo "                parameters (and do not submit the job)."
    echo " --show-params  Print a summary of the parameters specified in the job"
    echo "                after processing any command-line substitutionns (and"
    echo "                do not submit the job)."
    echo " --open         Open the job page in a browser after submission."
}

SHOW_JOB=no
SHOW_PARAMS=no
OPEN=no
SUBSTS=''
while [ $# -gt 0 ]; do
    case $1 in
        --show-job)
            SHOW_JOB=yes
            ;;
        --show-params)
            SHOW_PARAMS=yes
            SHOW_JOB=yes
            ;;
        --open)
            OPEN=yes
            ;;
        --*)
            echo "unrecognized option $1"
            usage
            exit 1
            ;;
        *)
            if [ "${FILENAME+set}" = "set" ]; then
                SUBSTS="${SUBSTS:+$SUBSTS,}$1"
            else
                FILENAME=$1
            fi
            ;;
    esac
    shift
done

if [ "${FILENAME+set}" != "set" ]; then
    echo "Must pass a filename"
    usage
    exit 1
fi

tmpdir=$(mktemp -d)
cleanup () { rm -rf $tmpdir; }
trap cleanup 0
if [ "${FILENAME%%.yaml}" != "${FILENAME}" ] || [ "${FILENAME%%.yml}" != "${FILENAME}" ]; then
    python -c "import json, yaml, sys; print json.dumps(yaml.safe_load(open(sys.argv[1])), indent=2)" $FILENAME > $tmpdir/job.json
else
    python -c "import json, sys; print json.dumps(json.load(open(sys.argv[1])), indent=2)" $FILENAME > $tmpdir/job.json
fi
if [ -n "$SUBSTS" ] || [ "$SHOW_PARAMS" = "yes" ]; then
    python -c "
import json,sys
job = json.load(open(sys.argv[1]))
substs = {}
if sys.argv[2]:
    for kv in sys.argv[2].split(','):
        k, v = kv.split('=', 1)
        substs[k] = v
show_params = (sys.argv[3] == 'yes')
for action in job['actions']:
    if action['command'] != 'lava_test_shell':
        continue
    for parameter, values in action.get('parameters', {}).items():
        if parameter != 'testdef_repos':
            continue
        for value in values:
            if 'parameters' not in value:
                continue
            ps = value['parameters']
            if not ps:
                continue
            newps = {}
            if show_params:
                if 'git-repo' in value:
                    print value['git-repo']
                if 'bzr-repo' in value:
                    print value['bzr-repo']
            for k, v in sorted(ps.items()):
                newps[k] = substs.get(k, v)
                if show_params:
                    print '    ' + k + ':', newps[k]
            value['parameters'] = newps
if not show_params:
    print json.dumps(job, indent=2)
" $tmpdir/job.json "$SUBSTS" "$SHOW_PARAMS" > $tmpdir/job2.json
    mv $tmpdir/job2.json $tmpdir/job.json
fi

if [ "$SHOW_JOB" = "yes" ]; then
    cat $tmpdir/job.json
    exit 0
fi

lava scheduler submit-job ${LAVA_URL:=http://validation.linaro.org}/RPC2/ $tmpdir/job.json | tee $tmpdir/output.txt
if [ ${PIPESTATUS[0]} -eq 0 ] && [ "$OPEN" = yes ]; then
    cat $tmpdir/output.txt | python -c 'import re, sys
for l in sys.stdin:
 for m in re.findall("[0-9.]+", l): print m' | \
    while read job_id; do
        gnome-open ${LAVA_URL:=https://validation.linaro.org}/scheduler/job/$job_id
    done
fi
