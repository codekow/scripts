# version=F43
# see https://pykickstart.readthedocs.io/en/latest/kickstart-docs.html#chapter-2-kickstart-commands-in-fedora

# ksvalidator kickstart.ks

# Use text mode install
text

# Reboot after installation
reboot

# System timezone
timezone US/Central --utc

# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'

# System language
lang en_US.UTF-8

# SSH user - install only
sshpw --username root         --plaintext alongpassword
sshpw --username install      --plaintext alongpassword
sshpw --username install-user --plaintext alongpassword --lock

# Root user
# openssl passwd -6
# rootpw --iscrypted $6$Bk0u6peFc7ZfbG3D$3mxmnys1UMWzKDH733mmg/SWNKjkzRx3NUPkt.iOj7PaBMF9L4nzjfHZeukrwZgW5T4u0UBLoNyMyMiOm1lF7.
rootpw --lock

# Regular user
# user --groups=wheel,kvm,input,libvirt --uid 999 --gid 999 --gecos="Ansible" --name=ansible --password=alongpassword --plaintext
%include /tmp/inst.users

# Network information
# network --device=link --bootproto=dhcp --activate
%include /tmp/inst.network

# Use network installation
# url --url="http://mirrors.kernel.org/fedora/releases/43/Server/x86_64/os"
# repo --name=updates
# repo --name=fedora

# Install repos
%include /tmp/inst.repos

# Firewall configuration
firewall --enabled --port=8080:tcp,9090:tcp --service=http,https,ssh

# SELinux configuration
selinux --enforcing

firstboot --disable

# Do not configure the X Window System
skipx

# Clear the Master Boot Record
# zerombr

# Partition clearing information
%include /tmp/inst.disk
clearpart --initlabel --none

# System bootloader configuration
bootloader --location=mbr --append=""

# Disk partitioning information
# autopart --type=btrfs --encrypted --passphrase=alongpassword
%include /tmp/inst.part

part /boot    --fstype="ext4"  --size=1024
part btrfs.00 --fstype="btrfs" --size=10240 --maxsize=102400 --grow --encrypted --passphrase=alongpassword

btrfs none  --data=single --label=fedora btrfs.00
btrfs /     --subvol --name=root fedora
btrfs /home --subvol --name=home fedora

%include /tmp/inst.lvm
# logvol none --vgname=vmdata  --name=vm-01-sda --size=1024 --maxsize=102400 --grow
# logvol none --vgname=vmdata  --name=vm-01-sdb --size=102400 --grow

%packages

%include /tmp/inst.packages

%end

%pre --log=/root/ks-pre.log

# grep %include *.cfg
> /tmp/inst.users
> /tmp/inst.network
> /tmp/inst.repos
> /tmp/inst.disk
> /tmp/inst.part
> /tmp/inst.lvm
> /tmp/inst.packages

# ks_pre.sh

%end

%post --nochroot

  cp /root/ks-pre.log /mnt/sysroot/root
  cp /root/debug-pkgs.log /mnt/sysroot/root

%end

%post --log=/root/ks-post.log

# ks_post.sh

%end
