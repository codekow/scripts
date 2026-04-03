#!/bin/bash

gpg_backup(){
  GPG_IMPORT=${1}
  SOURCE=${2:-${HOME}}

  GPG_TMP=$(mktemp -d XXXXXXX.tmp)
  GNUPGHOME=${GPG_TMP}
  export GNUPGHOME

  trap gpg_backup_cleanup INT

  STAMP=$(date --iso)

  # gpg --import "${GPG_IMPORT}"

  # tar vzc "${SOURCE}" | \
  #   gpg --encrypt \
  #     --trust-model always \
  #     --recipient "${GPG_ID}" > backup-"${STAMP}".tgz.gpg

  tar vzc "${SOURCE}" | \
    gpg --encrypt \
      --trust-model always \
      --keyring "${GPG_IMPORT}" \
      --recipient "${GPG_ID}" > backup-"${STAMP}".tgz.gpg

  GPG_ID=$(gpg --list-packets <"${GPG_IMPORT}" | awk '$1=="keyid:"{print$2}' | head -n 1)
  echo "KEY: ${GPG_ID}"

  gpg_backup_cleanup

}

gpg_backup_cleanup(){
  echo "removing: ${GPG_TMP} ..."
  rm -rf -- "${GPG_TMP}"
  unset GNUPGHOME
}


gpg_backup_keygen(){
  GPG_TMP=$(mktemp -d XXXXXXX.tmp)
  GNUPGHOME=${GPG_TMP}
  export GNUPGHOME

  trap gpg_backup_cleanup INT

  gpg --quick-gen-key --batch --passphrase '' backup@null
  gpg --export -a > gpg.asc
  gpg --export-secret-keys -a > gpg-sec.asc

  gpg_backup_cleanup
}

gpg_check(){
  which gpg > /dev/null || { echo "[error] Install gpg"; return; }
}

gpg_usage(){

  echo "
  gpg --export -a > gpg.asc
  gpg --export-secret-keys -a > gpg-sec.asc
  
  gpg_backup gpg.asc $HOME

  gpg --import gpg-sec.asc
  gpg --decrypt backup-*tgz.gpg | tar vzx
  "
}

main(){
  gpg_check
  gpg_usage
}

main
