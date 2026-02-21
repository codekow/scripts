# Scripting OS Installs

Render kickstart

```sh
sed '/# ks_pre.sh/r ks_pre.sh
    /# ks_post.sh/r ks_post.sh' ks-fedora-*.tpl > ks-fedora-server.cfg
```