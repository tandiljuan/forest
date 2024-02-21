#!/bin/bash
#
# Where would you hide a tree? In a forest, of course.
#
# This script encrypt a file and conceal it among other files.

# ------------------------------------------------------------------------------

#######################################
# Catch `SIGTERM`
# @see http://unix.stackexchange.com/a/42292
#######################################
cleanup () {
    echo "Bye!"
    exit 0
}

trap cleanup SIGINT SIGTERM

#######################################
# Send error messages to STDERR.
# @see https://google.github.io/styleguide/shellguide.html#stdout-vs-stderr
# Arguments:
#   @string Error message
# Outputs:
#   Writes error message to stdout
#######################################
err () {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# ------------------------------------------------------------------------------

#######################################
# Script usage message
# Arguments:
#   None
# Outputs:
#   Writes usage message to stdout
#######################################
usage () {
    echo "Usage:

    $(basename "$0") COMMAND CONTENT_FILE

    Commands:

    help  This help message.
    seed  Create the forest to hide the content.
    find  Find the tree in the forest and display the content.
    chop  Chop the forest (find the tree) and get the content."
}

#######################################
# Ask user for password
# Globals:
#   PASSWORD
# Arguments:
#   None
#######################################
ask_password () {
    local password_1=''
    local password_2=''

    read -s -p "> Enter password: " password_1
    echo
    read -s -p "> Confirm password: " password_2
    echo

    if [[ "${password_1}" != "${password_2}" ]]; then
        err "The password does not match"
        exit 1
    fi

    PASSWORD="${password_1}"
}

#######################################
# Create a random file
# Globals:
#   RANDOM
# Arguments:
#   @string File name
#   @number File size
#   @number Random difference in size (non-zero)
#######################################
random_tree () {
    local file_name="${1}"
    local file_size="${2}"
    local size_diff="${3:-0}"

    # Random difference in size
    # -------------------------

    if (( $size_diff != 0 )); then
        local rand_diff=$(( ($RANDOM % 10) + 1 ))

        if (( $(( $RANDOM % 2 )) == 0 )); then
            file_size=$(( $file_size + $rand_diff ))
        else
            file_size=$(( $file_size - $rand_diff ))
        fi
    fi

    # Create the file
    # ---------------

    head -c "${file_size}" < /dev/urandom > "${file_name}"
}

#######################################
# Encrypt a file
# Arguments:
#   @string File name
#   @string Password
#   @number Shred file (non-zero)
# Outputs:
#   Writes encrypted file name to stdout
#######################################
hide_tree () {
    local file_name="${1}"
    local password="${2}"
    local shred_file="${3:-0}"

    local now="$(date +'%Y%m%d_%H%M%S_%N')"
    local tar_name="tree_wrapper_${now}.tar"
    local gpg_name="tree_gpg_${now}.gpg"
    local md5_name=''

    # Wrap file
    # ---------

    tar --create --file "${tar_name}" "${file_name}"

    if (( $shred_file != 0 )); then
        shred -u --zero --iterations=2 "${file_name}"
    else
        rm "${file_name}"
    fi

    md5_name=$(md5sum "${tar_name}" | cut -d' ' -f1)

    mv "${tar_name}" "${md5_name}"

    # Encrypt file
    # ------------
    # @see https://github.com/SixArm/gpg-encrypt

    gpg --quiet --no-greeting \
        --no-use-agent \
        --passphrase "${password}" \
        --symmetric \
        --cipher-algo AES256 \
        --digest-algo SHA256 \
        --cert-digest-algo SHA512 \
        --s2k-mode 3 \
        --s2k-digest-algo SHA512 \
        --s2k-count 65011712 \
        --force-mdc \
        --output "${gpg_name}" \
        "${md5_name}"

    if (( $shred_file != 0 )); then
        shred -u --zero --iterations=2 "${md5_name}"
    else
        rm "${md5_name}"
    fi

    # Rename and echo new name
    # ------------------------

    md5_name=$(md5sum "${gpg_name}" | cut -d' ' -f1)

    mv "${gpg_name}" "${md5_name}"

    echo "${md5_name}"
}

#######################################
# Unpack forest
# Arguments:
#   @string File name
# Outputs:
#   Writes directory name to stdout
#######################################
unpack_forest () {
    local file_name="${1}"
    local dir_name=$(tar -tf "${file_name}" | head -n1 | cut -d'/' -f1)

    tar -xf "${file_name}"

    echo "${dir_name}"
}

#######################################
# Search hidden tree
# Arguments:
#   @string Directory name
#   @string Password
# Outputs:
#   Writes file name to stdout
#######################################
search_tree () {
    local dir_name="${1}"
    local password="${2}"
    local hidden_tree=''

    for check_tree in $(ls -1 "${dir_name}"/); do
        gpg --quiet --no-greeting \
            --no-use-agent \
            --passphrase "${password}" \
            --decrypt \
            --output /dev/null \
            "${dir_name}/${check_tree}" &> /dev/null

        if [[ "$?" -eq 0 ]]; then
            hidden_tree="${check_tree}"
            break
        fi
    done

    echo "${hidden_tree}"
}

# ------------------------------------------------------------------------------

#######################################
# Seed the forest
# Globals:
#   FILE_NAME
#   PASSWORD
# Arguments:
#   None
#######################################
handle_seed () {
    # Ask number of trees
    # -------------------

    local qty_trees=1
    local regex='^[0-9]+$'

    read -p "> Enter amount of trees [1]: " qty_trees

    if ! [[ "${qty_trees}" =~ $regex ]] || (( $qty_trees < 1 )) ; then
        qty_trees=1
    fi

    qty_trees=$(( $qty_trees - 1 ))

    # Create forest directory
    # -----------------------

    local now="$(date +'%Y%m%d_%H%M%S_%N')"
    local dir_name="forest_${now}"

    mkdir -p "${dir_name}"

    # Create main tree
    # ----------------

    local main_size=$(stat --printf="%s" "${FILE_NAME}")
    local main_tree=$(hide_tree "${FILE_NAME}" "${PASSWORD}" 1)

    mv "${main_tree}" "${dir_name}"/

    echo "> Main tree: ${main_tree}"

    # Create random trees
    # -------------------

    for (( i=1; i<=$qty_trees; i++ )); do
        if (( $i == 1 )); then
            echo -n "> Random trees (${qty_trees}): "
        fi
        local now="$(date +'%Y%m%d_%H%M%S_%N')"
        local random_name="random_tree_${now}"
        local random_pass=$(head -c 1024 < /dev/urandom | base64 --wrap=0);
        random_tree "${random_name}" "${main_size}" 1
        random_name=$(hide_tree "${random_name}" "${random_pass}" 0)
        mv "${random_name}" "${dir_name}"/
        echo -n "."
        if (( $i == $qty_trees )); then
            echo
        fi
    done

    # Pack forest directory
    # ---------------------

    touch -a -m -t $(date +'%Y%m%d%H%M.%S') "${dir_name}"/*
    tar --create --file "${dir_name}.tar" "${dir_name}"
    local md5_name=$(md5sum "${dir_name}.tar" | cut -d' ' -f1)
    mv "${dir_name}.tar" "${md5_name}"
    rm -rf "${dir_name}"
    echo "> Forest name: ${md5_name}"
}

#######################################
# Find the hidden tree
# Globals:
#   FILE_NAME
#   PASSWORD
# Arguments:
#   @number List (0) or extract (non-zero)
#######################################
handle_find() {
    local list_content="${1:-0}"

    # Unpack forest
    # -------------

    local dir_name=$(unpack_forest "${FILE_NAME}")

    # Search tree
    # -----------

    local hidden_tree=$(search_tree "${dir_name}" "${PASSWORD}")

    # Display/extract content
    # -----------------------

    if [[ "${hidden_tree}" != "" ]]; then
        echo "> Hidden tree: ${hidden_tree}"

        local file_name=$(gpg --quiet --no-greeting \
            --no-use-agent \
            --passphrase "${PASSWORD}" \
            --decrypt \
            --output - \
            "${dir_name}/${hidden_tree}" \
            | tar --list)

        echo "> Tree content: ${file_name}"

        if (( $list_content != 0 )); then
            gpg --quiet --no-greeting \
                --no-use-agent \
                --passphrase "${PASSWORD}" \
                --decrypt \
                --output - \
                "${dir_name}/${hidden_tree}" \
                | tar --extract
            shred -u --zero --iterations=2 "${FILE_NAME}"
            echo "> Forest chopped"
        fi
    else
        echo "> Could not find the hidden tree"
    fi

    # Remove temporal directory
    # -------------------------

    rm -rf "${dir_name}"
}

#######################################
# Extract content from hidden tree
# Globals:
#   FILE_NAME
#   PASSWORD
# Arguments:
#   None
#######################################
handle_chop() {
    local extract_content=1

    handle_find "${extract_content}"
}

# ------------------------------------------------------------------------------

# Get sub-command and file name
# -----------------------------

COMMAND=$(echo "${@}" | cut -d' ' -f1)
FILE_NAME=$(echo "${@}" | cut -d' ' -f2-)

if [[ "${COMMAND}" == "${FILE_NAME}" ]]; then
    FILE_NAME=""
fi

if [[ "${COMMAND}" == "help" ]]; then
    usage
    exit
fi

if [[ "${COMMAND}" != "seed" ]] && [[ "${COMMAND}" != "find" ]] && [[ "${COMMAND}" != "chop" ]]; then
    err "Invalid command"
    usage
    exit 1
fi

if [ ! -f "${FILE_NAME}" ] || [ ! -r "${FILE_NAME}" ] || [ ! -s "${FILE_NAME}" ]; then
    err "File can not be read or is empty"
    echo
    usage
    exit 1
fi

# Request password
# ----------------

PASSWORD=''
ask_password

# Call sub-command
# ----------------

"handle_${COMMAND}"
