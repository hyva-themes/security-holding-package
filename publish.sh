#!/usr/bin/env bash
#
# Publishes this placeholder package under every name in PACKAGES.
#
# npm runs in a throwaway Docker container, so Node.js and npm are not needed on the host.
# You log in to npm inside the container, and the login is discarded when it exits.
#
# Usage:
#   ./publish.sh                          # publish all names in DEFAULT_PACKAGES, skipping published ones
#                                         # and deprecating those with a deprecation_message
#   ./publish.sh --dry-run                # extra arguments are passed to npm publish
#   PACKAGES=hyva-modules ./publish.sh    # publish selected names only
#   NODE_IMAGE=node:24-slim ./publish.sh  # use a different Node.js image
#
# A scoped name needs its npm org to exist before publishing.

set -euo pipefail

DEFAULT_PACKAGES="
    @hyva/about @hyvaio/about @hyva-commerce/about @hyva-checkout/about @hyva-modules/about
    hyva-commerce hyva-checkout hyva-modules
"
PACKAGES="${PACKAGES:-$DEFAULT_PACKAGES}"
NODE_IMAGE="${NODE_IMAGE:-node:24-slim}"

# npm install shows this warning for the package, pointing people who mistyped the name to the real one.
deprecation_message() {
    case "$1" in
        hyva-modules) echo "Did you mean @hyva-themes/hyva-modules?" ;;
    esac
}

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
        --env PACKAGES="$PACKAGES" \
        --env npm_config_browser=false \
        --env npm_config_update_notifier=false \
        --volume "$(cd "$(dirname "$0")" && pwd):/src:ro" \
        "$NODE_IMAGE" bash /src/publish.sh "$@"
fi

# Inside the container from here on.
# Work on a copy, so setting the package name never touches the mounted host files.
cp -R /src /tmp/package
cd /tmp/package

dry_run=""
if [[ " $* " == *" --dry-run "* ]]; then
    dry_run=1
else
    npm login
fi

version="$(npm pkg get version | tr -d '"')"
for package in $PACKAGES; do
    # Skip what an earlier, interrupted run already published, so re-running is safe.
    if [ -n "$(npm view "${package}@${version}" version 2> /dev/null)" ]; then
        echo "Skipping ${package}@${version}: already published"
    else
        echo "Publishing ${package}"
        npm pkg set name="${package}"
        npm publish "$@"
    fi

    # npm deprecates single versions, so a new version must be deprecated again.
    message="$(deprecation_message "$package")"
    if [ -n "$message" ]; then
        echo "Deprecating ${package}@${version}: ${message}"
        if [ -z "$dry_run" ]; then
            npm deprecate "${package}@${version}" "$message"
        fi
    fi
done
