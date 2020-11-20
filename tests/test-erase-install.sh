#!/bin/bash

# erase-install
# by Graham Pugh.
#
# WARNING. This is a self-destruct script. Do not try it out on your own device!
#
# This script downloads and runs installinstallmacos.py from Greg Neagle,
# which expects you to choose a value corresponding to the version of macOS you wish to download.
# This script automatically fills in that value so that it can be run remotely.
#
# See README.md for details on use.
#
## or just run without an argument to check and download the installer as required and then run it to wipe the drive
#
# Requirements:
# macOS 10.13.4+ is already installed on the device (for eraseinstall option)
# Device file system is APFS
#
# NOTE: at present this script downloads a forked version of Greg's script so that it can properly automate the download process

# URL for downloading installinstallmacos.py
installinstallmacos_url="https://raw.githubusercontent.com/grahampugh/macadmin-scripts/master/installinstallmacos.py"

# Directory in which to place the macOS installer. Overridden with --path
installer_directory="/Applications"

# Temporary working directory
workdir="/Library/Management/erase-install"

# place any extra packages that should be installed as part of the erase-install into this folder. The script will find them and install.
# https://derflounder.wordpress.com/2017/09/26/using-the-macos-high-sierra-os-installers-startosinstall-tool-to-install-additional-packages-as-post-upgrade-tasks/
extras_directory="$workdir/extras"

# Display downloading and erasing messages if this is running on Jamf Pro
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

if [[ -f "$jamfHelper" ]]; then
    # Jamf Helper localizations - download window
    jh_dl_title_en="Downloading macOS"
    jh_dl_desc_en="We need to download the macOS installer to your computer; this will take several minutes."
    jh_dl_title_de="Download macOS"
    jh_dl_desc_de="Der macOS Installer wird heruntergeladen, dies dauert mehrere Minuten."
    # Jamf Helper localizations - erase lockscreen
    jh_erase_title_en="Erasing macOS"
    jh_erase_desc_en="This computer is now being erased and is locked until rebuilt"
    jh_erase_title_de="macOS Wiederherstellen"
    jh_erase_desc_de="Der Computer wird jetzt zurückgesetzt und neu gestartet"
    # Jamf Helper localizations - reinstall lockscreen
    jh_reinstall_title_en="Upgrading macOS"
    jh_reinstall_heading_en="Please wait as we prepare your computer for upgrading macOS."
    jh_reinstall_desc_en="This process will take approximately 5-10 minutes. Once completed your computer will reboot and begin the upgrade."
    jh_reinstall_title_de="Upgrading macOS"
    jh_reinstall_heading_de="Bitte warten, das Upgrade macOS wird ausgeführt."
    jh_reinstall_desc_de="Dieser Prozess benötigt ungefähr 5-10 Minuten. Der Mac startet anschliessend neu und beginnt mit dem Update."
    # Jamf Helper localizations - confirmation window
    jh_confirmation_title_en="Erasing macOS"
    jh_confirmation_desc_en="Are you sure you want to ERASE ALL DATA FROM THIS DEVICE and reinstall macOS?"
    jh_confirmation_title_de="macOS Wiederherstellen"
    jh_confirmation_desc_de="Möchten Sie wirklich ALLE DATEN VON DIESEM GERÄT LÖSCHEN und macOS neu installieren?"
    jh_confirmation_button_en="Yes"
    jh_confirmation_button_de="Ja"
    jh_confirmation_cancel_button_en="Cancel"
    jh_confirmation_cancel_button_de="Abbrechen"
    # Jamf Helper localizations - free space check
    jh_check_desc_en="The macOS upgrade cannot be installed on a computer with less than 15GB disk space."
    jh_check_desc_de="Die Installation von macOS ist auf einem Computer mit weniger als 15GB freien Festplattenspeicher nicht möglich."

    # Jamf Helper icon for download window
    jh_dl_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns"

    # Jamf Helper icon for confirmation dialog
    jh_confirmation_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"

    # Grab currently logged in user to set the language for Jamf Helper messages
    current_user=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}')
    language=$(/usr/libexec/PlistBuddy -c 'print AppleLanguages:0' "/Users/${current_user}/Library/Preferences/.GlobalPreferences.plist")
    if [[ $language = de* ]]; then
        user_language="de"
    else
        user_language="en"
    fi

    # set localisation variables
    jh_dl_title=jh_dl_title_${user_language}
    jh_dl_desc=jh_dl_desc_${user_language}
    jh_erase_title=jh_erase_title_${user_language}
    jh_erase_desc=jh_erase_desc_${user_language}
    jh_reinstall_title=jh_reinstall_title_${user_language}
    jh_reinstall_heading=jh_reinstall_heading_${user_language}
    jh_reinstall_desc=jh_reinstall_desc_${user_language}
    jh_confirmation_title=jh_confirmation_title_${user_language}
    jh_confirmation_desc=jh_confirmation_desc_${user_language}
    jh_confirmation_button=jh_confirmation_button_${user_language}
    jh_confirmation_cancel_button=jh_confirmation_cancel_button_${user_language}
    jh_check_desc=jh_check_desc_${user_language}
fi

# Functions
show_help() {
    echo "
    [erase-install] by @GrahamRPugh

    Usage:
    [sudo] ./erase-install.sh [--list] [--samebuild] [--sameos] [--move] [--path=/path/to]
                [--build=XYZ] [--overwrite] [--os=X.Y] [--version=X.Y.Z] [--beta]
                [--fetch-full-installer] [--erase] [--reinstall]

    [no flags]        Finds latest current production, non-forked version
                      of macOS, downloads it.
    --seedprogram=... Select a non-standard seed program
    --catalogurl=...  Select a non-standard catalog URL (overrides seedprogram)
    --samebuild       Finds the build of macOS that matches the
                      existing system version, downloads it.
    --sameos          Finds the version of macOS that matches the
                      existing system version, downloads it.
    --os=X.Y          Finds a specific inputted OS version of macOS if available
                      and downloads it if so. Will choose the latest matching build.
    --version=X.Y.Z   Finds a specific inputted minor version of macOS if available
                      and downloads it if so. Will choose the latest matching build.
    --build=XYZ       Finds a specific inputted build of macOS if available
                      and downloads it if so.
    --move            If not erasing, moves the
                      downloaded macOS installer to $installer_directory
    --path=/path/to   Overrides the destination of --move to a specified directory
    --erase           After download, erases the current system
                      and reinstalls macOS
    --confirm         Displays a confirmation dialog prior to erasing the current
                      system and reinstalling macOS. Only applicable with
                      --erase argument.
    --reinstall       After download, reinstalls macOS without erasing the
                      current system
    --overwrite       Download macOS installer even if an installer
                      already exists in $installer_directory
    --list            List available updates only (don't download anything)
    --extras=/path/to Overrides the path to search for extra packages
    --beta            Include beta versions in the search. Works with the no-flag
                      (i.e. automatic), --os and --version arguments.
    --fetch-full-installer
                      For compatible computers (10.15+) obtain the installer using
                      'softwareupdate --fetch-full-installer' method instead of
                      using installinstallmacos.py

    Note: If existing installer is found, this script will not check
          to see if it matches the installed system version. It will
          only check whether it is a valid installer. If you need to
          ensure that the currently installed version of macOS is used
          to wipe the device, use the --overwrite parameter.
    "
    exit
}

kill_process() {
    process="$1"
    if /usr/bin/pgrep "$process" >/dev/null ; then 
        /usr/bin/pkill "$process" && echo "   [erase-install] '$process' ended" || \
        echo "   [erase-install] '$process' could not be killed"
    fi
}

free_space_check() {
    free_disk_space=$(df -Pk . | column -t | sed 1d | awk '{print $4}')

    if [[ $free_disk_space -ge 15000000 ]]; then
        echo "   [free_space_check] OK - $free_disk_space KB free disk space detected"
    else
        echo "   [free_space_check] ERROR - $free_disk_space KB free disk space detected"
        "$jamfHelper" -windowType "utility" -description "${!jh_check_desc}" -alignDescription "left" -icon "$jh_confirmation_icon" -button1 "Ok" -defaultButton "0" -cancelButton "1"
        exit 1
    fi
}

check_installer_is_valid() {
    echo "   [check_installer_is_valid] Checking validity of $installer_app."
    # check installer validity:
    installer_build=$( /usr/bin/defaults read "$installer_app/Contents/Info.plist" DTSDKBuild )
    system_build=$( /usr/bin/sw_vers -buildVersion )

    # we need to break the build into component parts to compare versions
    # 1. Darwin version is older in the installer than on the system
    if [[ ${installer_build:0:2} -lt ${system_build:0:2} ]]; then 
        invalid_installer_found="yes"
    # 2. Darwin version matches but build letter (minor version) is older in the installer than on the system
    elif [[ ${installer_build:0:2} -eq ${system_build:0:2} && ${installer_build:2:1} < ${system_build:2:1} ]]; then
        invalid_installer_found="yes"
    elif [[ ${installer_build:0:2} -eq ${system_build:0:2} && ${installer_build:2:1} == ${system_build:2:1} ]]; then
        installer_build_minor=${installer_build:3:5}
        system_build_minor=${system_build:3:5}
        # 3. Darwin version and build letter (minor version) matches but build version numbers are older in the installer than on the system
       if [[ ${installer_build_minor//[!0-9]/} -lt ${system_build_minor//[!0-9]/} ]]; then
            invalid_installer_found="yes"
        # 4. Darwin version, build letter (minor version) and build version numbers matches but beta release letter is older in the installer than on the system (unlikely to ever happen, but just in case)
        elif [[ ${installer_build_minor//[!0-9]/} -eq ${system_build_minor//[!0-9]/} && ${installer_build_minor//[0-9]/} < ${system_build_minor//[0-9]/} ]]; then
            invalid_installer_found="yes"
        fi
    fi

    if [[ "$invalid_installer_found" == "yes" ]]; then
        echo "   [check_installer_is_valid] $installer_build < $system_build so not valid."
    else
        echo "   [check_installer_is_valid] $installer_build >= $system_build so valid."
    fi

    installmacOSApp="$installer_app"
}

check_installassistant_pkg_is_valid() {
    echo "   [check_installer_is_valid] Checking validity of $installer_pkg."
    # check InstallAssistant pkg validity
    # packages generated by installinstallmacos.py have the format InstallAssistant-version-build.pkg
    # Extracting an actual version from the package is slow as the entire package must be unpackaged
    # to read the PackageInfo file. 
    # We are here YOLOing the filename instead. Of course it could be spoofed, but that would not be
    # in anyone's interest to attempt as it will just make the script eventually fail.
    installer_pkg_build=$( basename "$installer_pkg" | sed 's|.pkg||' | cut -d'-' -f 3 )
    system_build=$( /usr/bin/sw_vers -buildVersion )
    if [[ "$installer_pkg_build" < "$system_build" ]]; then
        echo "   [check_installassistant_pkg_is_valid] $installer_pkg_build < $system_build so not valid."
        installassistant_pkg="$installer_pkg"
        invalid_installer_found="yes"
    else
        echo "   [check_installassistant_pkg_is_valid] $installer_pkg_build >= $system_build so valid."
        installassistant_pkg="$installer_pkg"
    fi
}

find_existing_installer() {
    # Search for an existing download
    # First let's see if this script has been run before and left an installer
    macos_dmg=$( find $workdir/*.dmg -maxdepth 1 -type f -print -quit 2>/dev/null )
    macos_sparseimage=$( find $workdir/*.sparseimage -maxdepth 1 -type f -print -quit 2>/dev/null )
    installer_app=$( find "$installer_directory/Install macOS"*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    installer_pkg=$( find $workdir/InstallAssistant*.pkg -maxdepth 1 -type f -print -quit 2>/dev/null )

    if [[ -f "$macos_dmg" ]]; then
        echo "   [find_existing_installer] Installer image found at $macos_dmg."
        hdiutil attach "$macos_dmg"
        installer_app=$( find '/Volumes/'*macOS*/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
        check_installer_is_valid
    elif [[ -f "$macos_sparseimage" ]]; then
        echo "   [find_existing_installer] Installer sparse image found at $macos_sparseimage."
        hdiutil attach "$macos_sparseimage"
        installer_app=$( find '/Volumes/'*macOS*/Applications/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
        check_installer_is_valid
    elif [[ -d "$installer_app" ]]; then
        echo "   [find_existing_installer] Installer found at $installer_app."
        app_is_in_applications_folder="yes"
        check_installer_is_valid
    elif [[ -f "$installer_pkg" ]]; then
        echo "   [find_existing_installer] InstallAssistant package found at $installer_pkg."
        check_installassistant_pkg_is_valid
    else
        echo "   [find_existing_installer] No valid installer found."
    fi
}

overwrite_existing_installer() {
    echo "   [overwrite_existing_installer] Overwrite option selected. Deleting existing version."
    existing_installer=$( find /Volumes/*macOS* -maxdepth 2 -type d -name "Install*.app" -print -quit 2>/dev/null )
    if [[ -d "$existing_installer" ]]; then
        echo "   [erase-install] Mounted installer will be unmounted: $existing_installer"
        existing_installer_mount_point=$(echo "$existing_installer" | cut -d/ -f 1-3)
        diskutil unmount force "$existing_installer_mount_point"
    fi
    rm -f "$macos_dmg" "$macos_sparseimage"
    rm -rf "$installer_app"
    app_is_in_applications_folder=""
}

move_to_applications_folder() {
    if [[ $app_is_in_applications_folder == "yes" ]]; then
        echo "   [move_to_applications_folder] Valid installer already in $installer_directory folder"
        return
    fi

    # if dealing with a package we now have to extract it and check it's valid
    if [[ -f "$installassistant_pkg" ]]; then
        echo "   [move_to_applications_folder] Extracting $installassistant_pkg to /Applications folder"
        /usr/sbin/installer -pkg "$installassistant_pkg" -tgt /
        install_macos_app=$( find /Applications -maxdepth 1 -name 'Install macOS*.app' -type d -print -quit 2>/dev/null )
        if [[ -d "$install_macos_app" && "$keep_pkg" != "yes" ]]; then
            echo "   [move_to_applications_folder] Deleting $installassistant_pkg"
            rm -f "$installassistant_pkg"
        fi
        return
    fi

    echo "   [move_to_applications_folder] Moving installer to $installer_directory folder"
    cp -R "$install_macos_app" $installer_directory/
    existing_installer=$( find /Volumes/*macOS* -maxdepth 2 -type d -name "Install*.app" -print -quit 2>/dev/null )
    if [[ -d "$existing_installer" ]]; then
        echo "   [move_to_applications_folder] Mounted installer will be unmounted: $existing_installer"
        existing_installer_mount_point=$(echo "$existing_installer" | cut -d/ -f 1-3)
        diskutil unmount force "$existing_installer_mount_point"
    fi
    rm -f "$macos_dmg" "$macos_sparseimage"
    echo "   [move_to_applications_folder] Installer moved to $installer_directory folder"
}

find_extra_packages() {
    # set install_package_list to blank.
    install_package_list=()
    for file in "$extras_directory"/*.pkg; do
        if [[ $file != *"/*.pkg" ]]; then
            echo "   [find_extra_installers] Additional package to install: $file"
            install_package_list+=("--installpackage")
            install_package_list+=("$file")
        fi
    done
}

run_fetch_full_installer() {
    # for 10.15+ we can use softwareupdate --fetch-full-installer
    current_seed=$(/System/Library/PrivateFrameworks/Seeding.framework/Versions/A/Resources/seedutil current | grep "Currently enrolled in:" | sed 's|Currently enrolled in: ||')
    echo "   [run_fetch_full_installer] Currently enrolled in $current_seed seed program."
    if [[ $seedprogram ]]; then
        echo "   [run_fetch_full_installer] Non-standard seedprogram selected"
        /System/Library/PrivateFrameworks/Seeding.framework/Versions/A/Resources/seedutil enroll $seedprogram
        /usr/sbin/softwareupdate -l -a
    fi

    softwareupdate_args=''
    if [[ $prechosen_version ]]; then
        echo "   [run_fetch_full_installer] Trying to download version $prechosen_version"
        softwareupdate_args+=" --full-installer-version $prechosen_version"
    fi
    # now download the installer
    echo "   [run_fetch_full_installer] Running /usr/sbin/softwareupdate --fetch-full-installer $softwareupdate_args"
    /usr/sbin/softwareupdate --fetch-full-installer $softwareupdate_args

    if [[ $? == 0 ]]; then
        # Identify the installer
        if find /Applications -maxdepth 1 -name 'Install macOS*.app' -type d -print -quit 2>/dev/null ; then
            install_macos_app=$( find /Applications -maxdepth 1 -name 'Install macOS*.app' -type d -print -quit 2>/dev/null )
            # if we actually want to use this installer we should check that it's valid
            if [[ $erase == "yes" || $reinstall == "yes" ]]; then 
                check_installer_is_valid
                if [[ $invalid_installer_found == "yes" ]]; then
                    echo "   [run_fetch_full_installer] The downloaded app is invalid for this computer. Try with --version or without --fetch-full-installer"
                    kill_process jamfHelper
                    exit 1
                fi
            fi
        else
            echo "   [run_fetch_full_installer] No install app found. I guess nothing got downloaded."
            kill_process jamfHelper
            exit 1
        fi
    else
        echo "   [run_fetch_full_installer] softwareupdate --fetch-full-installer failed. Try without --fetch-full-installer option."
        kill_process jamfHelper
        exit 1
    fi
}

get_installinstallmacos() {
    # grab installinstallmacos.py if not already there
    if [[ ! -d "$workdir" ]]; then
        echo "   [get_installinstallmacos] Making working directory at $workdir"
        mkdir -p $workdir
    fi

    if [[ ! -f "$workdir/installinstallmacos.py" || $force_installinstallmacos == "yes" ]]; then
        if [[ ! $no_curl ]]; then
            echo "   [get_installinstallmacos] Downloading installinstallmacos.py..."
            curl -H 'Cache-Control: no-cache' -s $installinstallmacos_url > "$workdir/installinstallmacos.py"
        fi
    fi
    # check it did actually get downloaded
    if [[ ! -f "$workdir/installinstallmacos.py" ]]; then
        echo "Could not download installinstallmacos.py so cannot continue."
        exit 1
    else
        echo "   [get_installinstallmacos] installinstallmacos.py is in $workdir"
        iim_downloaded=1
    fi
       
}

check_newer_available() {
    # Download installinstallmacos.py
    get_installinstallmacos

    # run installinstallmacos.py with list and then interrogate the plist
    [[ ! -f "$python_path" ]] && python_path=$(which python)
    "$python_path" "$workdir/installinstallmacos.py" --list --workdir="$workdir" > /dev/null
    i=0
    newer_build_found="no"
    while available_build=$( /usr/libexec/PlistBuddy -c "Print :result:$i:build" "$workdir/softwareupdate.plist" 2>/dev/null); do
        if [[ $available_build > $installer_build ]]; then
            echo "   [check_newer_available] $available_build > $installer_build"
            newer_build_found="yes"
            break
        fi
        i=$((i+1))
    done
    [[ $newer_build_found != "yes" ]] && echo "   [check_newer_available] No newer builds found"
}

run_installinstallmacos() {
    # Download installinstallmacos.py
    get_installinstallmacos

    # Use installinstallmacos.py to download the desired version of macOS
    installinstallmacos_args=''

    if [[ $list == "yes" ]]; then
        echo "   [run_installinstallmacos] List only mode chosen"
        installinstallmacos_args+="--list "
    else
        installinstallmacos_args+="--workdir=$workdir "
        installinstallmacos_args+="--ignore-cache "
    fi

    if [[ $pkg_installer ]]; then 
        installinstallmacos_args+="--pkg "
    else
        installinstallmacos_args+="--raw "
    fi

    if [[ $catalogurl ]]; then
        echo "   [run_installinstallmacos] Non-standard catalog URL selected"
        installinstallmacos_args+="--catalogurl $catalogurl "
    elif [[ $seedprogram ]]; then
        echo "   [run_installinstallmacos] Non-standard seedprogram selected"
        installinstallmacos_args+="--seedprogram $seedprogram "
    fi

    if [[ $beta == "yes" ]]; then
        echo "   [run_installinstallmacos] Beta versions included"
        installinstallmacos_args+="--beta "
    fi

    if [[ $prechosen_os ]]; then
        echo "   [run_installinstallmacos] Checking that selected OS $prechosen_os is available"
        installinstallmacos_args+="--os=$prechosen_os "
        [[ $erase == "yes" || $reinstall == "yes" ]] && installinstallmacos_args+="--validate "

    elif [[ $prechosen_version ]]; then
        echo "   [run_installinstallmacos] Checking that selected version $prechosen_version is available"
        installinstallmacos_args+="--version=$prechosen_version "
        [[ $erase == "yes" || $reinstall == "yes" ]] && installinstallmacos_args+="--validate "

    elif [[ $prechosen_build ]]; then
        echo "   [run_installinstallmacos] Checking that selected build $prechosen_build is available"
        installinstallmacos_args+="--build=$prechosen_build "
        [[ $erase == "yes" || $reinstall == "yes" ]] && installinstallmacos_args+="--validate "

    elif [[ $samebuild == "yes" ]]; then
        echo "   [run_installinstallmacos] Checking that current build $system_build is available"
        installinstallmacos_args+="--current "

    elif [[ $sameos == "yes" ]]; then
        system_version=$( /usr/bin/sw_vers -productVersion )
        system_os_major=$( echo "$system_version" | cut -d '.' -f 1 )
        system_os_version=$( echo "$system_version" | cut -d '.' -f 2 )
        echo "   [run_installinstallmacos] Checking that current OS $system_os_major.$system_os_version is available"
        installinstallmacos_args+="--os=$system_os_major.$system_os_version "
        [[ $erase == "yes" || $reinstall == "yes" ]] && installinstallmacos_args+="--validate "

    elif [[ ! $list ]]; then
        #statements
        echo "   [run_installinstallmacos] Getting current production version"
        installinstallmacos_args+="--auto "
    fi

    python "$workdir/installinstallmacos.py" --warnings $installinstallmacos_args

    if [[ $list == "yes" ]]; then
        exit 0
    fi

    if [[ $? -gt 0 ]]; then
        echo "   [run_installinstallmacos] Error obtaining valid installer. Cannot continue."
        kill_process jamfHelper
        echo
        exit 1
    fi

    # Identify the installer dmg
    macos_dmg=$( find $workdir -maxdepth 1 -name 'Install_macOS*.dmg' -type f -print -quit )
    macos_sparseimage=$( find $workdir -maxdepth 1 -name 'Install_macOS*.sparseimage' -type f -print -quit )
    installer_pkg=$( find $workdir/InstallAssistant*.pkg -maxdepth 1 -type f -print -quit 2>/dev/null )

    if [[ -f "$macos_dmg" ]]; then
        echo "   [run_installinstallmacos] Mounting disk image to identify installer app."
        hdiutil attach "$macos_dmg"
        install_macos_app=$( find '/Volumes/'*macOS*/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    elif [[ -f "$macos_sparseimage" ]]; then
        echo "   [run_installinstallmacos] Mounting sparse disk image to identify installer app."
        hdiutil attach "$macos_sparseimage"
        install_macos_app=$( find '/Volumes/'*macOS*/Applications/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    elif [[ -f "$installer_pkg" ]]; then
        echo "   [run_installinstallmacos] InstallAssistant package downloaded."
    else
        echo "   [run_installinstallmacos] No disk image found. I guess nothing got downloaded."
        kill_process jamfHelper
        exit
    fi
}

# Main body

# Safety mechanism to prevent unwanted wipe while testing
erase="no"
reinstall="no"

while test $# -gt 0
do
    case "$1" in
        -l|--list) list="yes"
            ;;
        -e|--erase) erase="yes"
            ;;
        -r|--reinstall) reinstall="yes"
            ;;
        -m|--move) move="yes"
            ;;
        -s|--samebuild) samebuild="yes"
            ;;
        -t|--sameos) sameos="yes"
            ;;
        -o|--overwrite) overwrite="yes"
            ;;
        -x|--replace-invalid) replace_invalid_installer="yes"
            ;;
        -u|--update) update_installer="yes"
            ;;
        -c|--confirm) confirm="yes"
            ;;
        --beta) beta="yes"
            ;;
        --preservecontainer) preservecontainer="yes"
            ;;
        -f|--fetch-full-installer) ffi="yes"
            ;;
        --pkg) pkg_installer="yes"
            ;;
        --keep-pkg) keep_pkg="yes"
            ;;
        --force-curl) force_installinstallmacos="yes"
            ;;
        --no-curl) no_curl="yes"
            ;;
        --seedprogram)
            shift
            seedprogram="$1"
            ;;
        --catalogurl)
            shift
            catalogurl="$1"
            ;;
        --path)
            shift
            installer_directory="$1"
            ;;
        --pythonpath)
            shift
            python_path="$1"
            ;;
        --extras)
            shift
            extras_directory="$1"
            ;;
        --os)
            shift
            prechosen_os="$1"
            ;;
        --version)
            shift
            prechosen_version="$1"
            ;;
        --build)
            shift
            prechosen_build="$1"
            ;;
        --workdir)
            shift
            workdir="$1"
            ;;
        --seedprogram*)
            seedprogram=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --catalogurl*)
            catalogurl=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --path*)
            installer_directory=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --pythonpath*)
            python_path=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --extras*)
            extras_directory=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --os*)
            prechosen_os=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --version*)
            prechosen_version=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --build*)
            prechosen_build=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        --workdir*)
            workdir=$(echo $1 | sed -e 's|^[^=]*=||g')
            ;;
        -h|--help) show_help
            ;;
    esac
    shift
done

echo
echo "   [erase-install] Script execution started: $(date)"

# ensure computer does not go to sleep while running this script
pid=$$
echo "   [erase-install] Caffeinating this script (pid=$pid)"
/usr/bin/caffeinate -dimsu -w $pid &

# not giving an option for fetch-full-installer mode for now... /Applications is the path
if [[ $ffi ]]; then
    installer_directory="/Applications"
fi

# ensure installer_directory exists
/bin/mkdir -p "$installer_directory"

# variable to prevent installinstallmacos getting downloaded twice
iim_downloaded=0

# some cli options vary based on installer versions
os_version=$( /usr/bin/defaults read "/System/Library/CoreServices/SystemVersion.plist" ProductVersion )
os_minor_version=$( echo "$os_version" | sed 's|^10\.||' | sed 's|\..*||' )

# Look for the installer, download it if it is not present
echo "   [erase-install] Looking for existing installer"
find_existing_installer

if [[ $invalid_installer_found == "yes" && -d "$install_macos_app" && $replace_invalid_installer == "yes" ]]; then
    overwrite_existing_installer
elif [[ $invalid_installer_found == "yes" && ($pkg_installer && ! -f "$installassistant_pkg") && $replace_invalid_installer == "yes" ]]; then
    echo "   [erase-install] Deleting invalid installer package"
    rm -f "$install_macos_app"
elif [[ $update_installer == "yes" && -d "$install_macos_app" && $overwrite != "yes" ]]; then
    echo "   [erase-install] Checking for newer installer"
    check_newer_available
    if [[ $newer_build_found == "yes" ]]; then 
        echo "   [erase-install] Newer installer found so overwriting existing installer"
        overwrite_existing_installer
    fi
elif [[ $update_installer == "yes" && ($pkg_installer && -f "$installassistant_pkg") && $overwrite != "yes" ]]; then
    echo "   [erase-install] Checking for newer installer"
    check_newer_available
    if [[ $newer_build_found == "yes" ]]; then 
        echo "   [erase-install] Newer installer found so deleting existing installer package"
        rm -f "$install_macos_app"
    fi
elif [[ $overwrite == "yes" && -d "$install_macos_app" && ! $list ]]; then
    overwrite_existing_installer
elif [[ $overwrite == "yes" && ($pkg_installer && -f "$installassistant_pkg") && ! $list ]]; then
    echo "   [erase-install] Deleting invalid installer package"
    rm -f "$installassistant_pkg"
elif [[ $invalid_installer_found == "yes" && ($erase == "yes" || $reinstall == "yes") ]]; then
    echo "   [erase-install] ERROR: Invalid installer is present. Run with --overwrite option to ensure that a valid installer is obtained."
    exit 1
fi

if [[ (! -d "$install_macos_app" && ! -f "$installassistant_pkg") || $list ]]; then
    echo "   [erase-install] Starting download process"
    # if using Jamf and due to erase, open a helper hud to state that
    # the download is taking place.
    if [[ -f "$jamfHelper" && ($erase == "yes" || $reinstall == "yes") ]]; then
        echo "   [erase-install] Opening jamfHelper download message (language=$user_language)"
        "$jamfHelper" -windowType hud -windowPosition ul -title "${!jh_dl_title}" -alignHeading center -alignDescription left -description "${!jh_dl_desc}" -lockHUD -icon  "$jh_dl_icon" -iconSize 100 &
    fi
    # now run installinstallmacos or softwareupdate
    if [[ $ffi && $os_minor_version -ge 15 ]]; then
        echo "   [erase-install] OS version is $os_version so can run with --fetch-full-installer option"
        run_fetch_full_installer
    else
        run_installinstallmacos
    fi
    # Once finished downloading, kill the jamfHelper
    kill_process "jamfHelper"
fi

if [[ $erase != "yes" && $reinstall != "yes" ]]; then
    if [[ -d "$install_macos_app" ]]; then
        echo "   [erase-install] Installer is at: $install_macos_app"
    fi

    # Move to $installer_directory if move_to_applications_folder flag is included
    # Not allowed for fetch_full_installer option
    if [[ $move == "yes" && ! $ffi ]]; then
        echo "   [erase-install] Invoking --move option"
        move_to_applications_folder
    fi

    # Unmount the dmg
    if [[ ! $ffi ]]; then
        existing_installer=$(find /Volumes/*macOS* -maxdepth 2 -type d -name "Install*.app" -print -quit 2>/dev/null )
        if [[ -d "$existing_installer" ]]; then
            echo "   [erase-install] Mounted installer will be unmounted: $existing_installer"
            existing_installer_mount_point=$(echo "$existing_installer" | cut -d/ -f 1-3)
            diskutil unmount force "$existing_installer_mount_point"
        fi
    fi
    # Clear the working directory
    echo "   [erase-install] Cleaning working directory '$workdir/content'"
    rm -rf "$workdir/content"
    # kill caffeinate
    kill_process "caffeinate"
    echo
    exit
fi

# Run the installer
echo
if [[ ! -d "$install_macos_app" ]]; then
    echo "   [erase-install] ERROR: Can't find the installer! "
    exit 1
fi
[[ $erase == "yes" ]] && echo "   [erase-install] WARNING! Running $install_macos_app with eraseinstall option"
[[ $reinstall == "yes" ]] && echo "   [erase-install] WARNING! Running $install_macos_app with reinstall option"
echo

# if ! pgrep -q Finder ; then
#     echo "    [erase-install] ERROR! The startosinstall binary requires a user to be logged in."
#     echo
#     exit 1
# fi

# also check that there is enough disk space
free_space_check

# If configured to do so, display a confirmation window to the user. Note: default button is cancel
if [[ $confirm == "yes" ]] && [[ -f "$jamfHelper" ]]; then
    if [[ $erase == "yes" ]]; then
        confirmation=$("$jamfHelper" -windowType utility -title "${!jh_confirmation_title}" -alignHeading center -alignDescription natural -description "${!jh_confirmation_desc}" \
            -lockHUD -icon "$jh_confirmation_icon" -button1 "${!jh_confirmation_cancel_button}" -button2 "${!jh_confirmation_button}" -defaultButton 1 -cancelButton 1 2> /dev/null)
        buttonClicked="${confirmation:$i-1}"

        if [[ "$buttonClicked" == "0" ]]; then
            echo "   [erase-install] User DECLINED erase/install"
            exit 0
        elif [[ "$buttonClicked" == "2" ]]; then
            echo "   [erase-install] User CONFIRMED erase/install"
        else
            echo "   [erase-install] User FAILED to confirm erase/install"
            exit 1
        fi
    else
        echo "   [erase-install] --confirm requires --erase argument; ignoring"
    fi
elif [[ $confirm == "yes" ]] && [[ ! -f "$jamfHelper" ]]; then
    echo "   [erase-install] Error: cannot obtain confirmation from user without jamfHelper. Cannot continue."
    exit 1
fi

# Jamf Helper icons for erase and re-install windows
jh_erase_icon="$install_macos_app/Contents/Resources/InstallAssistant.icns"
jh_reinstall_icon="$install_macos_app/Contents/Resources/InstallAssistant.icns"

if [[ -f "$jamfHelper" && $erase == "yes" ]]; then
    echo "   [erase-install] Opening jamfHelper full screen message (language=$user_language)"
    "$jamfHelper" -windowType fs -title "${!jh_erase_title}" -alignHeading center -heading "${!jh_erase_title}" -alignDescription center -description "${!jh_erase_desc}" -icon "$jh_erase_icon" &
elif [[ $reinstall == "yes" ]]; then
    echo "   [erase-install] Opening jamfHelper full screen message (language=$user_language)"
    "$jamfHelper" -windowType fs -title "${!jh_reinstall_title}" -alignHeading center -heading "${!jh_reinstall_heading}" -alignDescription center -description "${!jh_reinstall_desc}" -icon "$jh_reinstall_icon" &
    #statements
fi

# determine SIP status, as the volume is required if SIP is disabled
/usr/bin/csrutil status | grep -q 'disabled' && sip="disabled" || sip="enabled"

# set install argument for erase option
install_args=()
if [[ $erase == "yes" ]]; then
    install_args+=("--eraseinstall")
elif [[ $reinstall == "yes" && $sip == "disabled" ]]; then
    volname=$(diskutil info / | grep "Volume Name" | awk '{ print $(NF-1),$NF; }')
    install_args+=("--volume")
    install_args+=("/Volumes/$volname")
fi

# check for packages then add install_package_list to end of command line (empty if no packages found)
find_extra_packages

# some cli options vary based on installer versions
installer_build=$( /usr/bin/defaults read "$install_macos_app/Contents/Info.plist" DTSDKBuild )

# add --preservecontainer to the install arguments if specified (for macOS 10.14 (Darwin 18) and above)
if [[ "$installer_build" > "18A" && $preservecontainer == "yes" ]]; then
    install_args+=("--preservecontainer")
fi

# OS X 10.12 (Darwin 16) requires the --applicationpath option
if [[ $installer_build < "17A" ]]; then
    install_args+=("--applicationpath")
    install_args+=("$install_macos_app")
# macOS 10.15 (Darwin 19) and above require the --forcequitapps and --allowremoval options
elif [[ $installer_build > "19A" ]]; then
    install_args+=("--forcequitapps")
    install_args+=("--allowremoval")
fi

# run it!
# "$install_macos_app/Contents/Resources/startosinstall" "${install_args[@]}" --agreetolicense --nointeraction "${install_package_list[@]}"

# # kill Self Service if running
# kill_process "Self Service"
# # kill Jamf FUD if startosinstall ends before a reboot
# kill_process "jamfHelper"
