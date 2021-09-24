#!/bin/bash

. helpers/error.sh
. helpers/prompt.sh

echo "Setting up the FFXIV Environment scripts."
echo
echo "This script will require you to open the FFXIV launcher from Lutris as if you were going to play the game normally."
echo

FFXIV_PID="$(ps axo pid,cmd | grep -P '^\s*\d+\s+[A-Z]:\\.*\\XIVLauncher.exe$' | grep -vi grep | sed -e 's/^[[:space:]]*//' | cut -d' ' -f1 | head -1)"

if [[ "$FFXIV_PID" == "" ]]; then
    warn "Please open XIVLauncher. Checking for process \"XIVLauncher.exe\"..."
    while [[ "$FFXIV_PID" == "" ]]; do
        sleep 1
        FFXIV_PID="$(ps axo pid,cmd | grep -P '^\s*\d+\s+[A-Z]:\\.*\\XIVLauncher\.exe$'| grep -vi grep | sed -e 's/^[[:space:]]*//' | cut -d' ' -f1 | head -1)"
    done
fi

success "XIVLauncher PID found! ($FFXIV_PID)"
echo "Building environment information based on XIVLauncher env..."

FFXIV_ENVIRON="$(cat /proc/$FFXIV_PID/environ | xargs -0 bash -c 'printf "export %q\n" "$@"')"

REQ_ENV_VARS_REGEX="(DRI_PRIME|LD_LIBRARY_PATH|PYTHONPATH|SDL_VIDEO_FULLSCREEN_DISPLAY|WINEDLLPATH|WINEPREFIX|WINE_MONO_OVERRIDES|WINEESYNC|PROTON_VR_RUNTIME|WINEDLLOVERRIDES|WINELOADERNOEXEC|WINEPRELOADRESERVE|DXVK|export WINE=)"

FFXIV_ENVIRON_FINAL="$(echo "$FFXIV_ENVIRON" | grep -P "$REQ_ENV_VARS_REGEX")"

# Add FFXIV game path to environment for use in stage3 scripts
FFXIV_PATH=$(readlink -f /proc/$FFXIV_PID/cwd)
FFXIV_ENVIRON_FINAL=$FFXIV_ENVIRON_FINAL
FFXIV_ENVIRON_FINAL="$FFXIV_ENVIRON_FINAL"$'\n'"export FFXIV_PATH=\"$FFXIV_PATH\"" 

WINE_PATH="$(echo "$FFXIV_ENVIRON_FINAL" | grep 'export WINE=' | cut -d'=' -f2)"
WINE_DIST_PATH="$(dirname "$(dirname "$WINE_PATH")")"

WINEPREFIX="$(echo "$FFXIV_ENVIRON_FINAL" | grep 'export WINEPREFIX=' | cut -d'=' -f2  | sed -e 's/\\ / /g')"

# Check for wine 6. Not supporting anything else at the current time
if ![[ "$(echo "$FFXIV_ENVIRON_FINAL" | grep 'export WINE=')" == *wine/lutris-6.* ]]; then
    error "Detected that you're running this against a Wine prefix that is not Wine 6."
    error "This script only supports Wine 6. Please try again on a valid target prefix."
    exit 1
fi

# Check for wine already being setcap'd, fail if so
if [[ "$(getcap "$WINE_PATH")" != "" ]]; then
    error "Detected that you're running this against an already configured Wine (the binary at path \"$WINE_PATH\" has capabilities set already)."
    error "You must run this script against a fresh Wine install, or else the LD_LIBRARY_PATH environment variable configured by your runtime cannot be detected."
    exit 1
fi

if [[ "$(echo "$FFXIV_ENVIRON_FINAL" | grep 'export LD_LIBRARY_PATH=')" == "" ]]; then
    warn "Unable to determine runtime LD_LIBRARY_PATH."
    warn "This may indicate something strange with your setup."
    warn "Continuing is not advised unless you know how to fix any issues that may come up related to missing libraries."
    exit 1
fi

echo
success "Detected the following information about your setup. If any of this looks incorrect, please abort and report a bug to the Github repo..."
echo "Runtime Environment: Lutris"
echo "wine Executable Location: $WINE_PATH"
echo "Proton Distribution Path: $WINE_DIST_PATH"
echo "Wine Prefix: $WINEPREFIX"
echo

PROMPT_CONTINUE

echo "Creating destination directory at $HOME/bin if it doesn't exist."

mkdir -p "$HOME/bin"

echo "Creating source-able environment script at: $HOME/bin/ffxiv-env-setup.sh"

cat << EOF > $HOME/bin/ffxiv-env-setup.sh
#!/bin/bash
$FFXIV_ENVIRON_FINAL
export WINEDEBUG=-all
export WINE_PATH="$WINE_PATH"
export WINE_DIST_PATH="$WINE_DIST_PATH"
export WINEPREFIX="$WINEPREFIX"
export PATH="$WINE_DIST_PATH/bin:\$PATH"
EOF

chmod +x $HOME/bin/ffxiv-env-setup.sh

echo "Creating environment wrapper at: $HOME/bin/ffxiv-env.sh"

cat << EOF > $HOME/bin/ffxiv-env.sh
#!/bin/bash
. $HOME/bin/ffxiv-env-setup.sh
cd \$WINEPREFIX
/bin/bash
EOF

chmod +x $HOME/bin/ffxiv-env.sh
