#!/bin/bash

set -eu

usage () {
    echo "usage: sj [options] JOB_FILE param=value"
}

SHOW_ONLY=no
OPEN=no
SUBSTS=''
while [ $# -gt 0 ]; do
    case $1 in
        --show)
            SHOW_ONLY=yes
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
if [ -n "$SUBSTS" ]; then
    python -c "
import json,sys
job = json.load(open(sys.argv[1]))
substs = {}
for kv in sys.argv[2].split(','):
    k, v = kv.split('=', 1)
    substs[k] = v
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
            newps = {}
            for k, v in ps.items():
                newps[k] = substs.get(k, v)
            value['parameters'] = newps
print json.dumps(job, indent=2)
" $tmpdir/job.json "$SUBSTS" > $tmpdir/job2.json
    mv $tmpdir/job2.json $tmpdir/job.json
fi

if [ "$SHOW_ONLY" = "yes" ]; then
    cat $tmpdir/job.json
    exit 0
fi

exit 0

lava scheduler submit-job https://$USER@validation.linaro.org/RPC2/ $tmpdir/job.json | tee $tmpdir/output.txt
if [ ${PIPESTATUS[0]} -eq 0 ] && [ "$OPEN" = yes ]; then
    job_id=$(awk '/submitted as/ { print $5 }' $tmpdir/output.txt)
    gnome-open https://validation.linaro.org/scheduler/job/$job_id
fi
