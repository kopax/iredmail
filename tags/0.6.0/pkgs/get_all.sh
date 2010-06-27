#!/usr/bin/env bash

# Author:   Zhang Huangbin (michaelbibby <at> gmail.com)
# Purpose:  Fetch all extra packages we need to build mail server.

#---------------------------------------------------------------------
# This file is part of iRedMail, which is an open source mail server
# solution for Red Hat(R) Enterprise Linux, CentOS, Debian and Ubuntu.
#
# iRedMail is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# iRedMail is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with iRedMail.  If not, see <http://www.gnu.org/licenses/>.
#---------------------------------------------------------------------

ROOTDIR="$(pwd)"
CONF_DIR="${ROOTDIR}/../conf"

. ${CONF_DIR}/global
. ${CONF_DIR}/functions
. ${CONF_DIR}/core
. ${CONF_DIR}/iredadmin

# Re-define @STATUS_FILE, so that iRedMail.sh can read it.
export STATUS_FILE="${ROOTDIR}/../.${PROG_NAME}.installation.status"

check_user root
check_hostname

if [ X"${DISTRO}" == X"FREEBSD" ]; then
    FETCH_CMD='ftp -i'
else
    FETCH_CMD="wget -cq --referer ${PROG_NAME}-${PROG_VERSION}-${DISTRO}-X${DISTRO_CODENAME}-${ARCH}"
fi

#
# Mirror site.
# Site directory structure:
#
#   ${MIRROR}/
#           |- yum/         # for RHEL/CentOS
#               |- rpms/
#                   |- 5/
#                   |- 6/   # Not present yet.
#               |- misc/    # Source tarballs.
#               |- srpms/   # Source RPMs.
#           |- apt/             # for Debian/Ubuntu
#               |- debian/      # For Debian
#                   |- lenny/   # For Debian (Lenny)
#
# You can find nearest mirror in this page:
#   http://code.google.com/p/iredmail/wiki/Mirrors
#

# Where to store binary packages and source tarball.
PKG_DIR="${ROOTDIR}/pkgs"
MISC_DIR="${ROOTDIR}/misc"

if [ X"${DISTRO}" == X"RHEL" ]; then
    export MIRROR='http://iredmail.org/yum'

    # Special package.
    # command: which.
    export BIN_WHICH='which'
    export PKG_WHICH="which.${ARCH}"
    # command: wget.
    export BIN_WGET='wget'
    export PKG_WGET="wget.${ARCH}"

elif [ X"${DISTRO}" == X"DEBIAN" -o X"${DISTRO}" == X"UBUNTU" ]; then
    export MIRROR='http://iredmail.org/apt'

    if [ X"${ARCH}" == X"x86_64" ]; then
        export pkg_arch='amd64'
    else
        export pkg_arch="${ARCH}"
    fi

    if [ X"${DISTRO}" == X"DEBIAN" ]; then
        export PKGFILE="MD5.debian"             # File contains MD5.
        export PKGLIST="$( cat ${ROOTDIR}/${PKGFILE} | grep -E "(_${pkg_arch}|_all)" | awk -F'pkgs/' '{print $2}' )"
        export MD5LIST="$( cat ${ROOTDIR}/${PKGFILE} | grep -E "(_${pkg_arch}|_all)" )"

    fi

    export fetch_pkgs="fetch_pkgs_debian"   # Function used to fetch binary packages.
    export create_repo="create_repo_debian" # Function used to create apt repository.

    # Special package.
    # command: which.
    export BIN_WHICH='which'
    export PKG_WHICH="debianutils"
    # command: wget.
    export BIN_WGET='wget'
    export PKG_WGET="wget"
    # command: dpkg-scanpackages.
    export BIN_CREATEREPO="dpkg-scanpackages"
    export PKG_CREATEREPO="dpkg-dev"
else
    export MIRROR='http://iredmail.org/yum'
fi

# Binary packages.
export pkg_total=$(echo ${PKGLIST} | wc -w | awk '{print $1}')
export pkg_counter=1

# Misc file (source tarball) list.
if [ X"${DISTRO}" == X"FREEBSD" ]; then
    PKGMISC='SHASUM.freebsd.misc'
elif [ X"${DISTRO}" == X"UBUNTU" -a X"${DISTRO_CODENAME}" == X"lucid" ]; then
    PKGMISC='MD5.ubuntu.lucid'
else
    PKGMISC='MD5.misc'
fi
MISCLIST="$(cat ${ROOTDIR}/${PKGMISC} | awk -F'misc/' '{print $2}')"


mirror_notify()
{
    cat <<EOF
*********************************************************************
**************************** Mirrors ********************************
*********************************************************************
* If you can't fetch packages, please try to use another mirror site
* listed in below url:
*
*   - http://code.google.com/p/iredmail/wiki/Mirrors
*
*********************************************************************
EOF

    echo 'export status_mirror_notify="DONE"' >> ${STATUS_FILE}
}

prepare_dirs()
{
    ECHO_INFO "Creating necessary directories ..."
    for i in ${PKG_DIR} ${MISC_DIR}
    do
        [ -d "${i}" ] || mkdir -p "${i}"
    done
}

fetch_pkgs_debian()
{
    if [ X"${DOWNLOAD_PKGS}" == X"YES" ]; then
        cd ${PKG_DIR}

        if [ X"${PKGLIST}" != X"0" ]; then
            ECHO_INFO "==================== Fetching Binary Packages ===================="
            for i in ${PKGLIST}; do
                if [ X"${DISTRO}" == X"DEBIAN" ]; then
                    url="${MIRROR}/debian/lenny/${i}"
                fi

                ECHO_INFO "* ${pkg_counter}/${pkg_total}: ${url}"
                ${FETCH_CMD} "${url}"

                pkg_counter=$((pkg_counter+1))
            done
        else
            ECHO_INFO "============== Fetching Binary Packages [ SKIP ] =============="
        fi
    else
        :
    fi
}

fetch_misc()
{
    if [ X"${DOWNLOAD_PKGS}" == X"YES" ]; then
        # Fetch all misc packages.
        cd ${MISC_DIR}

        misc_total=$(( $(echo ${MISCLIST} | wc -w | awk '{print $1}') ))
        misc_count=1

        ECHO_INFO "==================== Fetching Source Tarballs ===================="

        for i in ${MISCLIST}
        do
            url="${MIRROR}/misc/${i}"
            ECHO_INFO "* ${misc_count}/${misc_total}: ${url}"

            ${FETCH_CMD} "${url}"

            misc_count=$((misc_count + 1))
        done
    else
        :
    fi
}

check_md5()
{
    cd ${ROOTDIR}

    if [ X"${DISTRO}" != X"FREEBSD" ]; then
        ECHO_INFO -n "Validate Packages ..."

        md5file="/tmp/check_md5_tmp.${RANDOM}$RANDOM}"
        echo -e "${MD5LIST}" > ${md5file}
        cat ${PKGMISC} >> ${md5file}
        md5sum -c ${md5file} |grep 'FAILED'
        RETVAL="$?"
        rm -f ${md5file} 2>/dev/null

        if [ X"${RETVAL}" == X"0" ]; then
            echo -e "\t[ FAILED ]"
            ECHO_ERROR "MD5 check failed. Check your rpm packages. Script exit ...\n"
            exit 255
        else
            echo -e "\t[ OK ]"
            echo 'export status_fetch_pkgs="DONE"' >> ${STATUS_FILE}
            echo 'export status_fetch_misc="DONE"' >> ${STATUS_FILE}
            echo 'export status_check_md5="DONE"' >> ${STATUS_FILE}
        fi
    fi
}

create_repo_rhel()
{
    # createrepo
    ECHO_INFO "Generating yum repository ..."

    # Backup old repo file.
    backup_file ${LOCAL_REPO_FILE}

    # Generate new repo file.
    cat > ${LOCAL_REPO_FILE} <<EOF
[${LOCAL_REPO_NAME}]
name=${LOCAL_REPO_NAME}
baseurl=${YUM_UPDATE_REPO}
enabled=1
gpgcheck=0
priority=1
EOF

    echo 'export status_create_yum_repo="DONE"' >> ${STATUS_FILE}
}

create_repo_debian()
{
    # Use dpkg-scanpackages to create a local apt repository.
    ECHO_INFO -n "Generating local apt repository ..."

    # Warning: Use relative path of binary packages.
    cd ${ROOTDIR} && \
    ( ${BIN_CREATEREPO} $(basename ${PKG_DIR}) /dev/null > ${PKG_DIR}/Packages ) 2>/dev/null

    echo -e "\t[ OK ]"

    ECHO_INFO -n "Append local repository to /etc/apt/sources.list ..."
    grep 'iRedMail_Local$' /etc/apt/sources.list >/dev/null
    [ X"$?" != X"0" ] && echo -e "deb file://${ROOTDIR} $(basename ${PKG_DIR})/   # iRedMail_Local" >> /etc/apt/sources.list

    echo -e "\t[ OK ]"

    ECHO_INFO -n "Update apt repository data (apt-get update) ..."
    apt-get update

}

echo_end_msg()
{
    cat <<EOF
********************************************************
* All tasks had been finished Successfully. Next step:
*
*   # cd ..
*   # bash ${PROG_NAME}.sh
*
********************************************************

EOF
}

if [ -e ${STATUS_FILE} ]; then
    . ${STATUS_FILE}
else
    echo '' > ${STATUS_FILE}
fi

prepare_dirs

# Ubuntu 9.04, FreeBSD doesn't need to download extra binary packages.
if [ X"${DISTRO}" == X"DEBIAN" ]; then
    check_pkg ${BIN_WHICH} ${PKG_WHICH} && \
    check_pkg ${BIN_WGET} ${PKG_WGET} && \
    check_pkg ${BIN_CREATEREPO} ${PKG_CREATEREPO} && \
    eval ${fetch_pkgs} && \
    create_repo_debian
else
    :
fi

# Create yum repository.
if [ X"${DISTRO}" == X"RHEL" ]; then
    check_pkg ${BIN_WHICH} ${PKG_WHICH} && \
    check_pkg ${BIN_WGET} ${PKG_WGET} && \
    create_repo_rhel
fi

fetch_misc && \
check_md5 && \
check_pkg ${BIN_DIALOG} ${PKG_DIALOG} && \
echo_end_msg && \
echo 'export status_get_all="DONE"' >> ${STATUS_FILE}