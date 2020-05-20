#!/bin/bash -eu
#
# Provision CentOS VMs (vagrant shell provisioner).
#


if [[ "$(id -u)" != "$(id -u vagrant)" ]]; then
    echo "The provisioning script must be run as the \"vagrant\" user!" >&2
    exit 1
fi


echo "provision.sh: Customizing the base system..."

readonly CENTOS_RELEASE="$(rpm -q --queryformat '%{VERSION}' centos-release | cut -d. -f1)"

sudo rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-$([[ "${CENTOS_RELEASE}" -lt 8 ]] && echo "CentOS-${CENTOS_RELEASE}" || echo "centosofficial")"

sudo yum -q -y clean all
sudo yum -q -y makecache $([[ "${CENTOS_RELEASE}" -ge 8 ]] && echo "--timer" || echo "fast")

# EPEL gives us some essential base-system extras...
sudo yum -q -y --nogpgcheck install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${CENTOS_RELEASE}.noarch.rpm" || true
sudo rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-${CENTOS_RELEASE}"

sudo yum -q -y install \
    avahi mlocate lsof iotop \
    htop nmap-ncat pv tree vim tmux ltrace strace \
    sysstat perf zip unzip bind-utils man-pages

# Minor cleanup...
sudo systemctl stop tuned.service firewalld.service
sudo systemctl -q disable tuned.service firewalld.service

# Set a local timezone (the default for CentOS boxes is EDT)...
sudo timedatectl set-timezone "Europe/Lisbon"
echo "VM local timezone: $(timedatectl | awk '/[Tt]ime\s+zone:/ {print $3}')"

[[ "${CENTOS_RELEASE}" -lt 8 ]] && sudo yum -q -y install ntpdate
sudo systemctl -q enable chronyd.service
sudo systemctl start chronyd.service

# This gives us an easly reachable ".local" name for the VM...
sudo systemctl -q enable avahi-daemon.service
sudo systemctl start avahi-daemon.service
echo "VM available from the host at: ${HOSTNAME}.local"

# Prevent locale from being forwarded from the host, causing issues...
if sudo grep -q '^AcceptEnv\s.*LC_' /etc/ssh/sshd_config; then
    sudo sed -i 's/^\(AcceptEnv\s.*LC_\)/#\1/' /etc/ssh/sshd_config
    sudo systemctl restart sshd.service
fi

# Generate the initial "locate" DB...
if [[ "${CENTOS_RELEASE}" -lt 8 ]]; then
    sudo test -x /etc/cron.daily/mlocate && sudo /etc/cron.daily/mlocate
else
    sudo systemctl start mlocate-updatedb.service
fi

# Some SELinux tools may complain if this file is missing...
sudo touch /etc/selinux/targeted/contexts/files/file_contexts.local

# If another (file) provisioner made the host user's credentials available
# to us (see the "Vagrantfile" for details), let it use "scp" and stuff...
if [[ -f /tmp/id_rsa.pub ]]; then
    pushd "${HOME}/.ssh" >/dev/null

    if [[ ! -f .authorized_keys.vagrant ]]; then
        cp authorized_keys .authorized_keys.vagrant
    fi

    cat .authorized_keys.vagrant /tmp/id_rsa.pub > authorized_keys
    chmod 0600 authorized_keys
    rm -f /tmp/id_rsa.pub

    popd >/dev/null
fi

# Make "vagrant ssh" sessions more comfortable by tweaking the
# configuration of some system utilities (eg. bash, vim, tmux)...
rsync -r --exclude=.DS_Store "${HOME}/shared/vagrant/skel/" "${HOME}/"
echo -n | sudo tee /etc/motd >/dev/null


echo "provision.sh: Configuring custom repositories..."

# NGINX mainline gives us an updated (but production-ready) version...
sudo rpm --import "https://nginx.org/keys/nginx_signing.key"
sudo tee "/etc/yum.repos.d/nginx-mainline.repo" >/dev/null <<EOF
[nginx-mainline]
name=NGINX Mainline
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
EOF

if [[ "${CENTOS_RELEASE}" -lt 8 ]]; then
    # IUS gives us recent (but stable) packages on previous CentOS releases...
    sudo yum -q -y --nogpgcheck install "https://repo.ius.io/ius-release-el${CENTOS_RELEASE}.rpm" || true
    sudo rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-IUS-${CENTOS_RELEASE}"

    # Starting with RHEL/CentOS 8, Red Hat recommends podman/buildah for container-based
    # projects and the official (upstream) Docker packages no longer install cleanly. :/
    sudo yum -q -y install bridge-utils
    sudo rpm --import "https://download.docker.com/linux/centos/gpg"
    sudo yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo" >/dev/null
fi

# No packages from the above repositories have been installed,
# but prepare things for that to (maybe) happen further below...
sudo yum -q -y makecache $([[ "${CENTOS_RELEASE}" -ge 8 ]] && echo "--timer" || echo "fast")


echo "provision.sh: Running project-specific actions..."

# Install extra packages needed for the project...
sudo yum -q -y install \
    git gcc gcc-c++ automake

# Additional project-specific customizations...
# [...]


echo "provision.sh: Done!"


# vim: set expandtab ts=4 sw=4:
