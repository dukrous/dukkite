#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

# Install 1Password
echo "Installing 1Password"

# On libostree systems, /opt is a symlink to /var/opt,
# which actually only exists on the live system. /var is
# a separate mutable, stateful FS that's overlaid onto
# the ostree rootfs. Therefore we need to install it into
# /usr/lib/1Password instead, and dynamically create a
# symbolic link /opt/1Password => /usr/local/lib/1Password
# upon boot.

# Prepare staging directory
mkdir -p /var/opt

# Can be "beta" or "stable"
RELEASE_CHANNEL="${ONEPASSWORD_RELEASE_CHANNEL:-stable}"

# Setup repo
cat << EOF > /etc/yum.repos.d/1password.repo
[1password]
name=1Password ${RELEASE_CHANNEL^} Channel
baseurl=https://downloads.1password.com/linux/rpm/${RELEASE_CHANNEL}/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

# Import signing key
rpm --import https://downloads.1password.com/linux/keys/1password.asc

# Install the packages.
rpm-ostree install 1password 1password-cli

# Clean up the yum repo (updates are baked into new images)
rm /etc/yum.repos.d/1password.repo -f

echo "$(ls -l /usr/local/)"

# Move the installed application
mv /opt/1Password /usr/local/lib/1Password

# Create needed symlinks
rm /usr/bin/1password
rm /usr/bin/1password-mcp
rm /usr/local/lib/1Password/onepassword-mcp
ln -s /usr/local/lib/1Password/1password /usr/bin/
ln -s /usr/local/lib/1Password/1password-mcp /usr/bin/
ln -s /usr/local/lib/1Password/1password-mcp /usr/local/lib/1Password/onepassword-mcp

# chrome-sandbox requires the setuid bit to be specifically set.
# See https://github.com/electron/electron/issues/17972
chmod 4755 /usr/local/lib/1Password/chrome-sandbox

# Normally, after-install.sh would create a group,
# "onepassword", right about now. But if we do that during
# the ostree build it'll disappear from the running system!
# I'm going to work around that by hardcoding GIDs and
# crossing my fingers that nothing else steps on them.
# These numbers _should_ be okay under normal use, but
# if there's a more specific range that I should use here
# please submit a PR!

# Specifically, GID must be > 1000, and absolutely must not
# conflict with any real groups on the deployed system.
# Normal user group GIDs on Fedora are sequential starting
# at 1000, so let's skip ahead and set to something higher.
GID_ONEPASSWORD="1500"
GID_ONEPASSWORDCLI="1600"

# BrowserSupport binary needs setgid. This gives no extra permissions to the binary.
# It only hardens it against environmental tampering.
BROWSER_SUPPORT_PATH="/usr/local/lib/1Password/1Password-BrowserSupport"

chgrp "${GID_ONEPASSWORD}" "${BROWSER_SUPPORT_PATH}"
chmod g+s "${BROWSER_SUPPORT_PATH}"

# onepassword-cli also needs its own group and setgid, like the other helpers.
chgrp "${GID_ONEPASSWORDCLI}" /usr/bin/op
chmod g+s /usr/bin/op

# Dynamically create the required groups via sysusers.d
# and set the GID based on the files we just chgrp'd
cat >/usr/lib/sysusers.d/onepassword.conf <<EOF
g onepassword ${GID_ONEPASSWORD}
EOF
cat >/usr/lib/sysusers.d/onepassword-cli.conf <<EOF
g onepassword-cli ${GID_ONEPASSWORDCLI}
EOF

# remove the sysusers.d entries created by onepassword RPMs.
# They don't magically set the GID like we need them to.
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-cli.conf


# Register path symlink
# We do this via tmpfiles.d so that it is created by the live system.
cat >/usr/lib/tmpfiles.d/onepassword.conf <<EOF
L  /opt/1Password  -  -  -  -  /usr/local/lib/1Password
EOF

# Install QEMU Tools
dnf5 --setopt=install_weak_deps=False install -y \
    rocm-hip \
    rocm-opencl \
    rocm-clinfo \
    rocm-smi \
    qemu \
    libvirt \
    qemu-kvm \
    virt-manager \
    edk2-ovmf \
    guestfs-tools

#### Example for enabling a System Unit File
# systemctl enable podman.socket
