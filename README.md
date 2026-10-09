# remote-image-paste

On macOS, copy an image, focus a remote [Tern](https://stencil.so/tern) pane, and upload it over SSH. The plugin puts the file in `~/.omp/image-inbox` on that host and pastes the server path into the current pane. It does not press Enter.

Install it on the computer running the Tern window, not on the remote host:

```sh
tern plugin install github.com/cangiolo/remote-image-paste
```

## Requirements

- macOS
- OpenSSH `ssh` and `scp` on the Mac
- A Tern remote whose display name is already a working non-interactive `ssh` target: an SSH config alias such as `gpu-zhouy1`, or `user@host` with no spaces. There is no host map. A display name that contains a space falls back to the host address.
- Key or agent authentication. `BatchMode` is on, so a password prompt fails. Accept the host key once with `ssh` before using the shortcut.

png, jpg, jpeg, gif, and webp only. A pure image on the clipboard is read as a file URL; a Finder file copy of an image works too. Text paste is left alone.

## Use

Press `Cmd+Option+Shift+I`, or run **Send clipboard image to the current remote** from the palette. `Cmd+V` does the same when a remote host is focused and the clipboard is a local image. Any other paste is replayed unchanged.

The default chord is `cmd+alt+shift+i`. Change or remove it in Preferences → Keyboard. The command id is `plugin.remote-image-paste.send-image`.

If `tern` is on the remote `PATH`, or at `~/.local/share/tern/build/tern`, the plugin asks that `tern` to paste the server path. That is what lets omp attach the file. If `tern` is missing or the paste fails, the absolute server path is inserted as text instead. Submit the prompt yourself either way.

This is not a multi-file Finder uploader. [tern-file-paste](https://github.com/vokativ/tern-file-paste) covers that, and it does not handle an image-only clipboard.

## Limits

- macOS only. Other systems get a toast and do not upload.
- The Tern display name and the SSH target must already match, including port and key. A different SSH alias needs an SSH config `Host` entry under the Tern name.
- A remote `tern send paste` is not acknowledged as an image chip. A successful exit only means the remote command ran.
- Reloading Tern during an upload can leave the file on the server without a pasted path.
