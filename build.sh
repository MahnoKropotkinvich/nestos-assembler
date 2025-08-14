#!/usr/bin/env bash
set -euo pipefail

# Keep this script idempotent for local development rebuild use cases:
# any consecutive runs should produce the same result.

arch=$(uname -m)

if [ $# -gt 1 ]; then
  echo Usage: "build.sh [CMD]"
  echo "Supported commands:"
  echo "    configure_user"
  echo "    configure_yum_repos"
  echo "    install_rpms"
  echo "    make_and_makeinstall"
  exit 1
fi

set -x
srcdir=$(pwd)

configure_yum_repos() {
    local version_id
    version_id=$(. /etc/os-release && echo ${VERSION_ID})
    # Add continuous tag for latest build tools and mark as required so we
    # can depend on those latest tools being available in all container
    # builds.
    rm -rf /etc/yum.repos.d/*

    # Consistent with the base image, current: openeuler 22.03-LTS-SP4
#    echo -e "[${version_id}-SP4-NestOS]\nname=NestOS\nenabled=1\nmetadata_expire=1m\nbaseurl=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/EPOL/multi_version/NestOS/For-Container/20240628/$arch/\ngpgcheck=0\npriority=2\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
 #   echo -e "[${version_id}-SP4-everything]\nname=everything\nenabled=1\nmetadata_expire=1m\nbaseurl=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/$arch/\ngpgcheck=0\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
  #  echo -e "[${version_id}-SP4-EPOL]\nname=EPOL\nenabled=1\nmetadata_expire=1m\nbaseurl=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/EPOL/main/$arch/\ngpgcheck=0\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
   echo -e "[${version_id}-patch]\nname=patch\nenabled=1\nmetadata_expire=1m\nbaseurl=https://build-repo.tarsier-infra.isrc.ac.cn/home:/mahno:/NestOS-patch/openEuler_24.03/\ngpgcheck=0\npriority=1\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo

 echo -e "[${version_id}-NestOS]\nname=NestOS\nenabled=1\nmetadata_expire=1m\nbaseurl=https://build-repo.tarsier-infra.isrc.ac.cn/home:/mahno:/openEuler_24.03_LTS_SP1_Epol_Multi-Version_NestOS_For-Container/openEuler_24.03_SP2_Everything/\ngpgcheck=0\npriority=2\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
    echo -e "[${version_id}-everything]\nname=everything\nenabled=1\nmetadata_expire=1m\nbaseurl=https://repo.openeuler.org/openEuler-24.03-LTS/everything/$arch/\ngpgcheck=0\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
    echo -e "[${version_id}-EPOL]\nname=EPOL\nenabled=1\nmetadata_expire=1m\nbaseurl=https://repo.openeuler.org/openEuler-24.03-LTS/EPOL/main/$arch/\ngpgcheck=0\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
    echo -e "[${version_id}-extra]\nname=extra\nenabled=1\nmetadata_expire=1m\nbaseurl=https://build-repo.tarsier-infra.isrc.ac.cn/home:/mahno:/NestOS-extra/openEuler_24.03/\ngpgcheck=0\npriority=1\nskip_if_unavailable=False\n" >> /etc/yum.repos.d/nestos-sp4.repo
}

install_rpms() {
    local builddeps
    local frozendeps

    # First, a general update; this is best practice.  We also hit an issue recently
    # where qemu implicitly depended on an updated libusbx but didn't have a versioned
    # requires https://bugzilla.redhat.com/show_bug.cgi?id=1625641
    yum -y distro-sync

    # xargs is part of findutils, which may not be installed
    yum -y install /usr/bin/xargs

    # These are only used to build things in here.  Today
    # we ship these in the container too to make it easier
    # to use the container as a development environment for itself.
    # Down the line we may strip these out, or have a separate
    # development version.
    builddeps=$(grep -v '^#' "${srcdir}"/src/build-deps.txt)

    # Process our base dependencies + build dependencies and install
    #(echo "${builddeps}" && echo "${frozendeps}" && "${srcdir}"/src/print-dependencies.sh) | xargs yum -y install
    (echo "${builddeps}" && "${srcdir}"/src/print-dependencies.sh) | xargs yum -y install

    # Add fast-tracked packages here.  We don't want to wait on bodhi for rpm-ostree
    # as we want to enable fast iteration there.
    #yum -y --enablerepo=updates-testing upgrade rpm-ostree

    # Allow Kerberos Auth to work from a keytab. The keyring is not
    # available in a Container.
    sed -e "s/^.*default_ccache_name/#    default_ccache_name/g" -i /etc/krb5.conf

    # Open up permissions on /boot/efi files so we can copy them
    # for our ISO installer image, skip if not present
    if [ -e /boot/efi ]; then
        chmod -R a+rX /boot/efi
    fi
    # Similarly for kernel data and SELinux policy, which we want to inject into supermin
    chmod -R a+rX /usr/lib/modules /usr/share/selinux/targeted
    # Further cleanup
    yum clean all
}

make_and_makeinstall() {
    make
    make install
    # Remove go build cache
    # https://github.com/coreos/coreos-assembler/issues/2872
    rm -rf /root/.cache/go-build
}

configure_user(){
    # modify Time Zone
    rm -f /etc/localtime
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # /dev/kvm might be bound in, but will have the gid from the host, and not all distros
    # a+rw permissions on /dev/kvm. create groups for all the common kvm gids and then add
    # builder to them.
    # systemd defaults to 0666 but other packages like qemu sometimes override this with 0660.
    # Adding the user to the kvm group should always work.

    # fedora uses gid 36 for kvm
    getent group kvm78  || groupadd -g 78 -o -r kvm78   # arch, gentoo
    getent group kvm124 || groupadd -g 124 -o -r kvm124 # debian
    getent group kvm232 || groupadd -g 232 -o -r kvm232 # ubuntu

    # We want to run what builds we can as an unprivileged user;
    # running as non-root is much better for the libvirt stack in particular
    # for the cases where we have --privileged in the container run for other reasons.
    # At some point we may make this the default.
    getent passwd builder || useradd builder --uid 1000 -G wheel,kvm,kvm78,kvm124,kvm232
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel-nopasswd
    # Contents of /etc/sudoers.d need not to be world writable
    chmod 600 /etc/sudoers.d/wheel-nopasswd
    # Allow the builder user to run rootless podman
    # Referenced at: https://github.com/containers/podman/issues/4056#issuecomment-1245715492
    # Lifted from: https://github.com/containers/podman/blob/6e382d9ec2e6eb79a72537544341e496368b6c63/contrib/podmanimage/stable/Containerfile#L25-L26
    echo -e "builder:1:999\nbuilder:1001:64535" > /etc/subuid
    echo -e "builder:1:999\nbuilder:1001:64535" > /etc/subgid
}

write_archive_info() {
    head -n -1 /etc/bashrc
    echo "TMOUT=32400" >> /etc/bashrc
    # shellcheck source=src/cmdlib.sh
    . "${srcdir}/src/cmdlib.sh"
    mkdir -p /cosa /lib/coreos-assembler
    touch -f /lib/coreos-assembler/.clean
    prepare_git_artifacts "${srcdir}" /cosa/coreos-assembler-git.json /cosa/coreos-assembler-git.tar.gz
}

if [ $# -ne 0 ]; then
  # Run the function specified by the calling script
  ${1}
else
  # Otherwise, just run all the steps.  NOTE: This is presently not actually
  # used in `Dockerfile`, so if you add a stage you'll need to do it both
  # here and there.
  configure_yum_repos
  install_rpms
  write_archive_info
  make_and_makeinstall
  configure_user
fi
