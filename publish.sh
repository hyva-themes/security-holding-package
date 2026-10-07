#!/usr/bin/env bash
#
# Publishes this placeholder package as @<scope>/about for every scope in SCOPES.
#
# npm runs in a throwaway Docker container, so Node.js and npm are not needed on the host.
# You log in to npm inside the container, and the login is discarded when it exits.
#
# Usage:
#   ./publish.sh                          # publish to @hyva, @hyvaio and @hyva-commerce
#   ./publish.sh --dry-run                # extra arguments are passed to npm publish
#   SCOPES=hyvaio ./publish.sh            # publish to selected scopes only
#   NODE_IMAGE=node:24-slim ./publish.sh  # use a different Node.js image

set -euo pipefail

SCOPES="${SCOPES:-hyva hyvaio hyva-commerce}"
PACKAGE="about"
NODE_IMAGE="${NODE_IMAGE:-node:24-slim}"

if [ -z "${IN_PUBLISH_CONTAINER:-}" ]; then
    if ! command -v docker > /dev/null; then
        echo "Docker is required to run $0" >&2
        exit 1
    fi

    tty_flags=(-i)
    if [ -t 0 ] && [ -t 1 ]; then
        tty_flags+=(-t)
    fi

    exec docker run --rm "${tty_flags[@]}" \
        --user node \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --env IN_PUBLISH_CONTAINER=1 \
        --env SCOPES="$SCOPES" \
        --env npm_config_browser=false \
        --env npm_config_update_notifier=false \
        --volume "$(cd "$(dirname "$0")" && pwd):/src:ro" \
        "$NODE_IMAGE" bash /src/publish.sh "$@"
fi

# Inside the container from here on.
# Work on a copy, so setting the package name never touches the mounted host files.
cp -R /src /tmp/package
cd /tmp/package

if [[ " $* " != *" --dry-run "* ]]; then
    npm login
fi

for scope in $SCOPES; do
    echo "Publishing @${scope}/${PACKAGE}"
    npm pkg set name="@${scope}/${PACKAGE}"
    npm publish "$@"
done
