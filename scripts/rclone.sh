#!/bin/sh
# https://zihad.com.bd/posts/how-to-setup-sync-google-drive-with-podman-container-and-rclone/

RCLONE_CONFIG=~/.config/rclone

rclone_bisync_cmd(){

  podman run --rm --name rclone-bisync \
    -v ~/.config/rclone:/config/rclone:Z \
    -v ~/.cache/rclone:/root/.cache/rclone:Z \
    -v ~/Remotes/"Google Drive":/data/remote:Z \
    docker.io/rclone/rclone:latest bisync "gdrive:/" "/data/remote" \
    $@
}

rclone_bisync(){

  rclone_bisync_cmd \
  --create-empty-src-dirs \
  --check-filename .nobackup \
  --compare size,modtime,checksum \
  --max-delete "50" \
  --fix-case \
  --check-access \
  --drive-acknowledge-abuse \
  --progress \
  --metadata \
  --resilient \
  --max-lock 2m \
  --recover \
  --verbose \
  $@
}

rclone_bisync_init(){
  rclone_bisync --resync
}
