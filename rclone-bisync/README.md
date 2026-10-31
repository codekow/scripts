# Setup Rclone BiSync

```sh
rsync -av rclone-bisync/.config/ ~/.config/

systemctl --user daemon-reload
systemctl --user enable rclone-bisync.timer
```
