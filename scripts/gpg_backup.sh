#!/bin/bash
# shellcheck disable=SC2034

gpg_backup(){
  GPG_IMPORT=${1}
  SOURCE=${2:-${HOME}}

  GPG_TMP=$(mktemp -d XXXXXXX.tmp)
  GNUPGHOME=${GPG_TMP}
  export GNUPGHOME

  STAMP=$(date --iso)
  
  gpg --import "${GPG_IMPORT}"
  GPG_ID=$(gpg --list-packets <"${GPG_IMPORT}" | awk '$1=="keyid:"{print$2}' | head -n 1)

  echo "KEY: ${GPG_ID}"

  tar vzc "${SOURCE}" | \
    gpg --encrypt \
      --trust-model always \
      --recipient ${GPG_ID} > backup-"${STAMP}".tgz.gpg

  rm -rf "${GPG_TMP}"
  unset GNUPGHOME
}

gpg_check(){
  which gpg > /dev/null || { echo "[error] Install gpg"; return; }
}

gpg_usage(){

  echo "
  gpg --export < name / id > -a > pub.asc
  gpg_backup pub.asc $HOME

  gpg --decrypt backup-*tgz.gpg | tar vzx
  "
}

main(){
  gpg_check
  gpg_usage
}

main
