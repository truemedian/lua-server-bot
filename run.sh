#!/bin/bash

RUN_SESSION_NAME="discord"
RUN_COMMAND="./bin/luvit init"
RUN_ERRLOG="./logs/stderr.log"

if [ -z $TMUX ]; then
    if ! command -v tmux >/dev/null; then
        echo "fatal: tmux not installed"
        exit 1
    fi

    tmux attach-session -t $RUN_SESSION_NAME 2>/dev/null && exit 0
    tmux new-session -s $RUN_SESSION_NAME $0 || exit 1

    exit 0
fi

if [ "$(tmux display-message -p '#S')" == "$RUN_SESSION_NAME" ]; then
    while true; do
        echo "[$(date)] [Running] $RUN_COMMAND" >> "$RUN_ERRLOG"

        $RUN_COMMAND 2> >(tee -a "$RUN_ERRLOG" >&2)

        code=$?

        echo "[Exit] exited with code=$code" >> "$RUN_ERRLOG"
        echo "" >> "$RUN_ERRLOG"
        if [ $code == 254 ]; then
            exit 0
        elif [ $code != 0 ]; then
            sleep 5s
        fi
    done
else
    echo "fatal: nesting tmux sessions is dangerous, please use this command outside of tmux."
fi
