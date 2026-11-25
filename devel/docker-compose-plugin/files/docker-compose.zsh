#compdef docker-compose
# Zsh completion wrapper for standalone docker-compose command
# Delegates to docker's native completion for the 'compose' subcommand

_docker-compose() {
    if ! whence -w _docker >/dev/null; then
        autoload -Uz _docker 2>/dev/null || true
    fi
    words=(docker compose "${words[@]:1}")
    (( CURRENT++ ))
    _docker "$@"
}

_docker-compose "$@"
