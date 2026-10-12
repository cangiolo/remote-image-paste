# remote-image-paste

On macOS, copy an image file, focus a remote [Tern](https://stencil.so/tern) pane, and explicitly upload it over SSH. The plugin puts the file in `~/.omp/image-inbox` on that host and inserts the server path as text into the initiating pane. It does not press Enter or change the clipboard.

Install it on the computer running the Tern window, not on the remote host:

```sh
tern plugin install github.com/cangiolo/remote-image-paste
```

## Requirements

- macOS
- OpenSSH `ssh` and `scp` on the Mac
- A Tern remote whose display name is already a working non-interactive `ssh` target: an SSH config alias such as `gpu-zhouy1`, or `user@host` with no spaces. There is no host map. A display name that contains a space falls back to the host address.
- Key or agent authentication. `BatchMode` is on, so a password prompt fails. Accept the host key once with `ssh` before using the shortcut.

png, jpg, jpeg, gif, and webp files only. The dedicated upload command accepts a clipboard file URL (including a Finder file copy) or an absolute local image path. Image-only clipboard data and ordinary text should use Tern's native `Cmd+V` instead.

## Use

Use **native `Cmd+V` for normal text and image attachments**, locally or remotely. This plugin no longer overrides `paste` or binds `Cmd+V`.

Only when you want to upload an image file and insert its remote path as text, press `Cmd+Option+Shift+I` or run **Send clipboard image to the current remote** from the palette. The destination is captured when the command starts; switching focus during upload does not redirect the result. If the pane closes, exits, changes host, or disconnects, insertion fails with the uploaded path shown in the error instead of targeting another pane. Local panes receive a remote-pane hint only for this dedicated command.

The default chord is `cmd+alt+shift+i`. Change or remove it in Preferences → Keyboard. The command id is `plugin.remote-image-paste.send-image`.

The command uses Tern's native pane-specific text insertion API, with no carriage return. It does not require a remote `tern` executable and does not create an image attachment chip. For attachment chips, use native `Cmd+V`; submit the prompt yourself.

This is not a multi-file Finder uploader. [tern-file-paste](https://github.com/vokativ/tern-file-paste) covers that, and it does not handle an image-only clipboard.

## Limits

- macOS only. Other systems get a toast and do not upload.
- The Tern display name and the SSH target must already match, including port and key. A different SSH alias needs an SSH config `Host` entry under the Tern name.
- A successful insertion call is not an acknowledgement from the receiving application and does not imply that an image attachment was created.
- Reloading Tern during an upload can leave the file on the server without a pasted path.

## Paste routing fix (2026-10-12)

- Removed automatic paste interception after a custom `Cmd+V` handler exceeded Tern's 50 ms hook budget and was disabled until reload.
- Reconnected upload completion to the captured pane, without title-based targeting, command execution, or clipboard replacement.
- Cleared the old `Cmd+V` override through the running window's settings API. Editing `settings.json` or reloading plugins alone did not update that window's active keymap. When migrating an existing window, replace `keybinds` through `cx.settings:set` with the shortcut omitted; an empty action array disables a shortcut rather than restoring its default.
- Verified native text paste locally and remotely, native image attachment chips in local and remote omp, and explicit upload with file-digest verification and a focus change before insertion.
