#!/usr/bin/env bash
# Bash completion wrapper for standalone docker-compose command
# Delegates to docker's native completion for the 'compose' subcommand

_docker_compose() {
    if ! declare -F _docker >/dev/null 2>&1; then
        if declare -F _completion_loader >/dev/null 2>&1; then
            _completion_loader docker 2>/dev/null || true
        fi
    fi
    if declare -F _docker >/dev/null 2>&1; then
        COMP_WORDS=(docker compose "${COMP_WORDS[@]:1}")
        (( COMP_CWORD++ ))
        _docker
    fi
}

complete -F _docker_compose -o default -o bashdefault docker-compose
