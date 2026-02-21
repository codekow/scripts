#!/bin/bash
# shellcheck disable=SC2188,SC2129
set -x

ks_init(){

# set install ttl
echo 69 > /proc/sys/net/ipv4/ip_default_ttl

# include users
# add users
echo '
user --groups=wheel,kvm,input,libvirt --uid 999 --gid 999   --name=ansible --password=alongpassword --plaintext --gecos="Ansible"
' > /tmp/inst.users

}

ks_unsorted(){

# include disk
> /tmp/inst.disk

check_disks

echo "ignoredisk --only-use=${DISK:-sda}" > /tmp/inst.disk

# include lvm
> /tmp/inst.lvm

if vgdisplay -s | grep -q vmdata; then
  echo "exists: vg vmdata"  
else
  echo "
part pv.00 --fstype=\"lvmpv\" --size=2048 --grow
volgroup vmdata --pesize=4096 pv.00
" > /tmp/inst.lvm
fi

# include part
> /tmp/inst.part

# efi detection
if [ -d "/sys/firmware/efi" ]; then
  echo 'part /boot/efi --fstype=efi --asprimary --size=200 --fsoptions="umask=0077,shortname=winnt"' > /tmp/inst.part
else
  echo 'part biosboot --fstype=biosboot --size=1' > /tmp/inst.part
fi

# include network
> /tmp/inst.network

# setup bridge
for NIC in /sys/class/net/e*
do
  NIC=${NIC##*/}
  INTERFACES=${NIC},${INTERFACES}
  echo "network --device=${NIC} --onboot=no" >> /tmp/inst.network
done

[ ! -z "${INTERFACES}" ] && \
  echo "network --device=br0 --bootproto=dhcp --bridgeslaves=${INTERFACES%,} --onboot=yes" >> /tmp/inst.network

}

disk_size(){
  DEVICE=${1:-sda}
  # disks - gibibytes
  # /sys/block/*/size is in 512 byte chunks
  DISK_GB=$(( $(< "/sys/block/${DEVICE}/size") / 2048 / 1024 ))
  echo "${DISK_GB}"
}

# disk detection
disk_ok(){
  DEVICE=${1:-sda}
  [ -e "/dev/${DEVICE}" ] || return 1
  [ "$(< "/sys/block/${DEVICE}/removable")" = 0 ] || return 1
  [ "16" -lt "$(disk_size "${DEVICE}")" ] || return 1
  blkid "${DEVICE}" >/dev/null && return 1
  DISK=${DEVICE}
}

check_disks(){
  disk_ok nvme0n1
  disk_ok sda
  disk_ok vda
}

set_repos(){
  OS_VER=${OS_VER:-43}
  
  # REPO_BASE=http://mirrors.kernel.org/fedora
  REPO_BASE=http://mirror.pilotfiber.com/fedora/linux
  REPO_URL=${1:-${REPO_BASE}/releases/${OS_VER}/Server/x86_64/os}

  # include repos
  > /tmp/inst.repos

  echo 'url --url="'"${REPO_URL}"'"' >> /tmp/inst.repos
  echo "repo --name=updates" >> /tmp/inst.repos
  echo "repo --name=fedora"  >> /tmp/inst.repos
}

set_packages(){
  CASE=${1}

  # include packages
  > /tmp/inst.packages

cat << BASE >> /tmp/inst.packages

# groups
@^server-product-environment
@container-management
@headless-management

BASE

[ -z "${CASE}" ] && return

cat << PACKAGES >> /tmp/inst.packages

# tpm / clevis / tang
clevis-*

# ops
bridge-utils
dnf-automatic
fio
gdisk
git
haveged
lm_sensors
lshw
memtest86+
nvme-cli
podman-docker
skopeo
smartmontools
testdisk
watchdog
xorg-x11-xauth

# virtual
guestfs-tools
libguestfs-tools
libvirt-daemon
libvirt-client
virt-manager
ksmtuned

# sushy-emulation
gcc
httpd-tools
ipmitool
libvirt-devel
python3-devel
python3-pip

# pretty
byobu
btop
htop
iotop
pv
tree
# fastfetch

# compression
pigz
pxz
zstd
p7zip-plugins

PACKAGES
}

main(){

  ks_init
  ks_unsorted

  set_packages all
  set_repos
}

main
