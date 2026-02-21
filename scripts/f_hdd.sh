#!/bin/bash

hdd_hdparm_hard_wipe(){
  CONFIRM=${1}
  DRIVE=${2}

  [ "$CONFIRM" == "YES" ] || return

  if [ -n "${DRIVE}" ]; then
    echo "
      hdparm --security-set-pass PASSWD ${DRIVE}
      hdparm --security-erase-enhanced PASSWD ${DRIVE}
      # hdparm --security-erase PASSWD ${DRIVE}
    " 
  else
    hdparm --security-help
  fi
}
