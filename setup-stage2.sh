#!/bin/bash

. helpers/error.sh
. helpers/prompt.sh

echo 'Setting up the Wine environment to run ACT with network capture.'
echo 'This script will set up your wine prefix to run ACT, as well as set up a default ACT install for you.'
echo 'If this process is aborted at any Continue prompt, it will resume from that point the next time it is run.'
echo 'Please make sure nothing is running in the wine prefix for FFXIV before continuing.'

if [ ! -f "$HOME/bin/ffxiv-env-setup.sh" ]; then
    error "The FFXIV environment hasn't been configured yet. Please run the stage1 setup first!"
    exit 1
fi

echo
echo 'Sourcing the FFXIV environment...'
. $HOME/bin/ffxiv-env-setup.sh

echo "Making sure wine isn't running anything."

FFXIV_PID="$(ps axo pid,cmd | grep -P '^\s*\d+\s+[A-Z]:\\.*\.exe$' | grep -vi grep | sed -e 's/^[[:space:]]*//' | cut -d' ' -f1)"

if [[ "$FFXIV_PID" != "" ]]; then
    warn "FFXIV launcher detected as running, forceably closing it."
    kill -9 $FFXIV_PID
fi

wine64 wineboot -fs &>/dev/null

WINE_VERSION_FULL=""
PROTON_VERSION_FULL=""

WINE_VERSION_FULL="$(echo $WINE_DIST_PATH | grep -oP 'lutris-(.+)' | cut -d'-' -f2)"

WINE_VERSION_MAJOR="$(echo $WINE_DIST_PATH | grep -oP 'lutris-(.+)' | cut -d'-' -f2 | cut -d'.' -f1)"
WINE_VERSION_MINOR="$(echo $WINE_DIST_PATH | grep -oP 'lutris-(.+)' | cut -d'-' -f2 | cut -d'.' -f2)"

if [[ "$WINE_VERSION_FULL" == "" || "$WINE_VERSION_MAJOR" == "" || "$WINE_VERSION_MINOR" == "" ]]; then
    echo
    error "Could not detect Proton version."
    exit 1   
fi

echo
warn 'Note that this process is destructive, meaning that if something goes wrong it can break your wine prefix installation.'
warn 'Please make backups!'

echo
echo "------------------------------------------------------------"
echo "Wine prefix: $WINEPREFIX"
echo "Proton distribution: $WINE_DIST_PATH"
echo "Proton version: ${WINE_VERSION_MAJOR}.${WINE_VERSION_MINOR}"
echo "------------------------------------------------------------"
echo

PROMPT_BACKUP

echo
echo "Would you like to continue installation?"

PROMPT_CONTINUE

echo
echo 'Checking for ACT install'
ACT_LOCATION="$WINEPREFIX/drive_c/ACT"

if [ -f "$WINEPREFIX/.ACT_Location" ]; then
    ACT_LOCATION="$(cat "$WINEPREFIX/.ACT_Location")"
else
    warn "Setup hasn't been run on this wine prefix before"
    echo "Searching for the ACT install may take some time if this prefix has been highly customized."
    PROMPT_CONTINUE

    echo
    TEMP_ACT_LOCATION="$(find "$WINEPREFIX" -name 'Advanced Combat Tracker.exe')"

    if [[ "$TEMP_ACT_LOCATION" == "" ]]; then
        warn 'Could not find ACT install, downloading and installing latest version'
        PROMPT_CONTINUE
        wget -O "/tmp/ACT.zip" "https://advancedcombattracker.com/includes/page-download.php?id=57" &>/dev/null
        mkdir -p "$ACT_LOCATION" &> /dev/null
        unzip -qq "/tmp/ACT.zip" -d "$ACT_LOCATION"
    else
        ACT_LOCATION="$(dirname "$TEMP_ACT_LOCATION")"
    fi
    success "Found ACT location at $ACT_LOCATION"
    echo "Saving this path to $WINEPREFIX/.ACT_Location for future use"
    echo "$ACT_LOCATION" > "$WINEPREFIX/.ACT_Location"
fi

echo "Making sure wine isn't running anything"
wine64 wineboot -s &>/dev/null

echo 'Checking to see if wine binaries and libraries need to be patched'

if [[ "$(patchelf --print-rpath "$(which wine)" | grep '$ORIGIN')" != "" || "$(patchelf --print-rpath "$(which wine)")" == "" ]]; then
    RPATH="${WINE_DIST_PATH}/lib64:${WINE_DIST_PATH}/lib"
    # Lutris requires extra runtimes from its install path
    RPATH="$RPATH:$(echo $LD_LIBRARY_PATH | tr ':' $'\n' | grep '/lutris/runtime/' | tr $'\n' ':')"
    echo 'Patching the rpath of wine executables and libraries'
    echo 'New rpath for binaries:'
    echo
    echo "$RPATH"
    echo "------------------------------------------------------------"
    PROMPT_CONTINUE
    
    patchelf --set-rpath "$RPATH" "$(which wine)"
    patchelf --set-rpath "$RPATH" "$(which wine64)"
    patchelf --set-rpath "$RPATH" "$(which wineserver)"
    
    # setup-stage1 will only run for verion 6 of Wine, which does not need the LIB RPATH patch
fi

echo 'Checking to see if wine binaries need their capabilities set'

if [[ "$(getcap "$(which wine)")" == "" ]]; then
    warn 'Setting capabilities on wine executables'
    warn 'This process must be run as root, so you will be prompted for your password'
    warn 'The commands to be run are as follows:'
    echo
    warn 'sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wine)"'
    warn 'sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wine64)"'
    warn 'sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wineserver)"'
    PROMPT_CONTINUE
    sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wine)"
    sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wine64)"
    sudo setcap cap_net_raw,cap_net_admin,cap_sys_ptrace=eip "$(which wineserver)"
fi
