#!/bin/bash
set -x

LUKS_DEFAULT="alongpassword"
LUKS_KEY_FILE=/root/luks-pass

genpass(){
  < /dev/urandom LC_ALL=C tr -dc Aa-zZ0-9 | head -c "${1:-32}"
}

get_luks_part(){
  for part in /dev/{s,v}d[a]* /dev/nvme0n1*
  do
    [ -e "${part}" ] || continue
    echo "${LUKS_DEFAULT}" | cryptsetup open --test-passphrase "${part}" - && LUKS_PART="${part}"
  done

  echo "${LUKS_PART}"
}

luks_add_random_key(){
  LUKS_PART=${1:-$(get_luks_part)}
  LUKS_PASS=${2:-$(genpass 8)-$(genpass 8)-$(genpass 8)-$(genpass 8)}
  LUKS_KEY_FILE="${LUKS_KEY_FILE:-/root/luks-pass}"
  LUKS_DEFAULT="${LUKS_DEFAULT:-alongpassword}"

  echo "${LUKS_PASS}" > "${LUKS_KEY_FILE}"

  printf '%s\n' "${LUKS_DEFAULT}" "${LUKS_PASS}" "${LUKS_PASS}" | \
    cryptsetup luksAddKey "${LUKS_PART}"
}

luks_remove_known_key(){
  printf '%s\n' "${LUKS_DEFAULT}" | \
    cryptsetup luksRemoveKey "${LUKS_PART}"
}

clevis_setup_root(){
  if [ -d "/sys/firmware/efi" ]; then
    systemd-analyze pcrs > /root/pcrs-ks

    # echo "${LUKS_DEFAULT}" | clevis luks bind -y -k - -d "${LUKS_PART}" tpm2 '{"pcr_ids":"0"}' || return
    cat "${LUKS_KEY_FILE}" | clevis luks bind -y -k - -d "${LUKS_PART}" tpm2 '{"pcr_ids":"0"}' || return

    luks_remove_known_key

  else
    return
  fi
}

clevis_create_script(){
  echo '#!/bin/bash
  clevis luks list -d '"${LUKS_PART}"'

  clevis luks unbind -f -d '"${LUKS_PART}"' -s1
  clevis luks unbind -f -d '"${LUKS_PART}"' -s2
  cat ${LUKS_KEY_FILE} | clevis luks bind -y -k - -d '"${LUKS_PART}"' tpm2 '"'"'{"pcr_ids":"0,1,2,3,4,5,6"}'"'"'

  echo '"${LUKS_DEFAULT}"' | cryptsetup luksRemoveKey '"${LUKS_PART}"' -
  ' > /root/clevis_boot.sh
  chmod +x /root/clevis_boot.sh
}

ssh_get_gh_key(){
  GH_USER=${1:-codekow}

  # github pub keys
  echo "# ${GH_USER}"
  curl -s "https://github.com/${GH_USER}.keys"
}

ssh_get_static_key(){
  # static ssh keys
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYyIA4ZQS7+keBHVKcFDVNmo7rHh0YHUGBCehAM1xTO not-a-secure-key"
}

ssh_add_user(){
  OS_USER=${1:-ansible}
  GH_USER=${2}

  useradd -m -U "${OS_USER}"
  usermod -a -G wheel,kvm,input,libvirt "${OS_USER}"

  OS_PATH=$(eval echo ~"${OS_USER}")

  mkdir -p "${OS_PATH}"/.ssh

  if [ -z "${GH_USER}" ]; then
    ssh_get_static_key >> "${OS_PATH}/.ssh/authorized_keys"
  else
    ssh_get_gh_key "${GH_USER}" >> "${OS_PATH}/.ssh/authorized_keys"
  fi

  # set user perms
  chmod 700 "${OS_PATH}/.ssh"
  chmod 600 "${OS_PATH}/.ssh/authorized_keys"
  chown -R "${OS_USER}": "${OS_PATH}/.ssh"

  # restore selinux context with restorecon, if it is available:
  command -v restorecon > /dev/null && restorecon -RvF "${OS_PATH}/.ssh" || true

  # sudo w/o password
  echo "${OS_USER}  ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${OS_USER}"
}

ssh_config_custom(){
  # disable password for ssh
  echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/40-no-password.conf
  command -v restorecon > /dev/null && restorecon -RvF /etc/ssh/sshd_config.d/40-no-password.conf || true
}

libvirt_config(){

cat << XML > /etc/libvirt/qemu/networks/macvtap.xml
<network>
  <name>macvtap</name>
  <forward dev="wlp4s0" mode="bridge">
  <forward dev="enp1s0" mode="bridge">
  </forward>
</network>
XML

cat << XML > /etc/libvirt/qemu/networks/bridged.xml
<network>
  <name>bridged</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
XML

  # virsh net-start bridged-network
  # virsh net-autostart bridged-network

  ln -s /etc/libvirt/qemu/networks/bridged.xml \
    /etc/libvirt/qemu/networks/autostart/

cat << XML > /etc/libvirt/storage/vmdata.xml
<pool type="logical">
  <name>vmdata</name>
  <source>
    <name>vmdata</name>
    <format type="lvm2"/>
  </source>
  <target>
    <path>/dev/vmdata</path>
  </target>
</pool>
XML

  ln -s /etc/libvirt/storage/vmdata.xml \
    /etc/libvirt/storage/autostart/

  # compress save image
  sed -i '/^save_image_format/d' /etc/libvirt/qemu.conf
  echo 'save_image_format = "gzip"' >> /etc/libvirt/qemu.conf

  systemctl enable libvirtd
  systemctl enable libvirt-guests
}

automatic_updates(){
  systemctl enable dnf5-automatic.timer

  # dnf5 missing config
  [ -f /etc/dnf/automatic.conf ] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/

  sed -i 's/apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
}

fix_udev_wol(){
  FILE=/etc/udev/rules.d/81-wol.rules
  echo 'ACTION=="add", SUBSYSTEM=="net", NAME=="en*", RUN+="/usr/sbin/ethtool -s $name wol g"' > ${FILE}
  command -v restorecon > /dev/null && restorecon -RvF ${FILE} || true
}

vbmcd_setup(){
  [ -d /opt/vbmc ] || \
    python3 -m venv --system-site-packages /opt/vbmc

  /opt/vbmc/bin/pip install -U pip
  /opt/vbmc/bin/pip install -U virtualbmc

cat <<EOF > /etc/systemd/system/vbmcd.service
[Unit]
Description = Virtual BMC for virtual machines
After = libvirtd.service
After = syslog.target
After = network.target

[Service]
Type = simple
User = ansible
Group = libvirt

ExecStart = /opt/vbmc/bin/vbmcd --foreground

Slice = vbmcd.slice
Restart = on-failure
RestartSec = 2
TimeoutSec = 120
ExecReload = /bin/kill -HUP \$MAINPID

[Install]
WantedBy = multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable vbmcd.service
  firewall-offline-cmd --add-port={6230/tcp,6231/tcp,6232/tcp,6233/tcp,6234/tcp}
}

sushy_setup(){
  [ -d /opt/vbmc ] || \
    python3 -m venv --system-site-packages /opt/vbmc

  /opt/vbmc/bin/pip install -U pip
  /opt/vbmc/bin/pip install -U sushy-tools gunicorn

sudo mkdir -p /etc/sushy/

cat << EOF > /etc/sushy/sushy-emulator.conf
SUSHY_EMULATOR_AUTH_FILE = '/etc/sushy/auth.conf'
SUSHY_EMULATOR_SSL_CERT = u'/etc/sushy/sushy.crt'
SUSHY_EMULATOR_SSL_KEY = u'/etc/sushy/sushy.key'
# SUSHY_EMULATOR_SSL_KEY = None
# SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_LISTEN_IP = u'0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = u'qemu:///system'
# SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
SUSHY_EMULATOR_BOOT_LOADER_MAP = {
    u'UEFI': {
        u'x86_64': u'/usr/share/OVMF/OVMF_CODE.secboot.fd'
    },
    u'Legacy': {
        u'x86_64': None
    }
}
EOF

# create sushy auth file
htpasswd -nb -B -C10 admin alongpassword > /etc/sushy/auth.conf

# create self signed cert
openssl req -x509 \
  -newkey rsa:4096 \
  -keyout /etc/sushy/sushy.key \
  -out /etc/sushy/sushy.crt \
  -sha256 \
  -days 3650 \
  -nodes -subj "/C=XX/ST=NA/L=NA/O=NA/OU=NA/CN=SushyEmulator"

chmod 770 /etc/sushy/
chmod 640 /etc/sushy/*
chown -Rv root:libvirt /etc/sushy/

cat <<EOF > /etc/systemd/system/sushy.service
[Unit]
Description = Sushy Redfish emulator for virtual machines
After = libvirtd.service
After = syslog.target
After = network.target

[Service]
LimitNOFILE=65535
Type = simple
User = ansible
Group = libvirt
Environment = "SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf"

# ExecStart = /opt/vbmc/bin/sushy-emulator \
#              --config /etc/sushy/sushy-emulator.conf \
#              --debug

ExecStart = /opt/vbmc/bin/gunicorn \
            -b 0.0.0.0:8000 \
            -w 1 \
            --log-level info \
            --certfile=/etc/sushy/sushy.crt \
            --keyfile=/etc/sushy/sushy.key \
            "sushy_tools.emulator.main:app"

Slice = sushy.slice
Restart = on-failure
RestartSec = 2
TimeoutSec = 120
ExecReload = /bin/kill -HUP \$MAINPID

[Install]
WantedBy = multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable sushy.service
  firewall-offline-cmd --add-port=8000/tcp
}

finalize(){
  # gzip faster
  if [ -e /bin/pigz ]; then
    ln -s /bin/pigz /usr/local/bin/gzip
    ln -s /bin/pigz /usr/local/bin/gunzip
  fi

  # enable haveged
  systemctl enable haveged

  # disable services
  systemctl disable ModemManager
  systemctl disable bluetooth
  systemctl disable cockpit.socket

  # autorelabel - just in case
  touch /.autorelabel

  # rebuild initramfs
  dracut -f
}

smartd_config(){
  sed -i 's/^DEVICESCAN/#DEVICESCAN/g' /etc/smartmontools/smartd.conf
  echo 'DEVICESCAN -a -o on -S on -s (S/../.././02|L/../../6/03) -H -m root -M exec /usr/libexec/smartmontools/smartdnotify -n standby,10,q' >> /etc/smartmontools/smartd.conf
}

kvm_blacklist(){
echo '# blacklist host gpu drivers
blacklist amdgpu
blacklist nouveau
' > /etc/modprobe.d/blacklist.conf
}

kvm_setup(){
  # not quiet
  sed -i '/^GRUB_CMDLINE_LINUX/ s/ rhgb quiet//' /etc/default/grub

  # enable nested virt
  sed -i 's/^# *options/options/' /etc/modprobe.d/kvm.conf

  # blacklist gpu drivers on host
  kvm_blacklist

  # enable iommu
  grep -q AuthenticAMD /proc/cpuinfo && CPU=amd
  grep -q GenuineIntel /proc/cpuinfo && CPU=intel

  if [ ! -z "${CPU}" ]; then
    sed -i '/^GRUB_CMDLINE_LINUX/ s/ '"${CPU}"'_iommu=on iommu=pt//' /etc/default/grub
    sed -i '/^GRUB_CMDLINE_LINUX/ s/"$/ '"${CPU}"'_iommu=on iommu=pt"/' /etc/default/grub
  fi

  # update grub.cfg
  grub2-mkconfig -o /boot/grub2/grub.cfg

}

main(){
  ssh_add_user ansible
  # ssh_add_user audrey adrezni
  # ssh_add_user cory codekow
  # ssh_add_user blake blakerblaker
  # ssh_add_user david davwhite
  # ssh_add_user eli guiderae
  # ssh_add_user rachelle rachellin8
  ssh_config_custom
  luks_add_random_key
  clevis_setup_root
  # clevis_create_script
  libvirt_config
  smartd_config
  automatic_updates
  fix_udev_wol
  vbmcd_setup
  sushy_setup
  kvm_setup
  finalize
}

main
