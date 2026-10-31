#!/bin/sh
# https://zihad.com.bd/posts/how-to-setup-sync-google-drive-with-podman-container-and-rclone/

RCLONE_CONFIG=${HOME}/.config/rclone
LOCAL_SYNC="${HOME}/Remotes/Google Drive"

rclone_bisync_podman(){
  podman run --rm --name rclone-bisync \
    -v ~/.config/rclone:/config/rclone:Z \
    -v ~/.cache/rclone:/root/.cache/rclone:Z \
    -v ~/Remotes/"Google Drive":/data/remote:Z \
    docker.io/rclone/rclone:latest bisync "gdrive:/" "/data/remote" \
    $@
}

rclone_bisync_cmd(){
  rclone bisync "gdrive:/" "${LOCAL_SYNC}" \
    $@
}

rclone_bisync(){
  rclone_bisync_podman \
    --log-level ERROR \
    --log-file /root/.cache/rclone/rclone.log \
    --create-empty-src-dirs \
    --compare size,modtime,checksum \
    --fix-case \
    --check-access \
    --drive-acknowledge-abuse \
    --progress \
    --metadata \
    --resilient \
    --max-lock 2m \
    --recover \
    --check-filename .nobackup \
    --max-delete "50" \
      $@

  find "${LOCAL_SYNC}" -name "*.conflict*"
}

rclone_bisync_init(){
  rclone_bisync_podman --resync
}
