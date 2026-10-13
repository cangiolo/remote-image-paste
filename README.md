# remote-image-paste

On macOS, copy an image file, focus a remote [Tern](https://stencil.so/tern) pane, and press `Cmd+V`. The plugin uploads the file over SSH to `~/.cache/remote-image-paste` and pastes its server path into the initiating pane using bracketed paste. In omp this creates an image attachment, not path text. It does not press Enter or change the clipboard.

Install it on the computer running the Tern window, not on the remote host:

```sh
tern plugin install github.com/cangiolo/remote-image-paste
```

## Requirements

- macOS
- OpenSSH `ssh` and `scp` on the Mac
- A Tern remote whose display name is already a working non-interactive `ssh` target: an SSH config alias such as `gpu-zhouy1`, or `user@host` with no spaces. There is no host map. A display name that contains a space falls back to the host address.
- Key or agent authentication. `BatchMode` is on, so a password prompt fails. Accept the host key once with `ssh` before using the shortcut.

png, jpg, jpeg, gif, and webp files only. File URLs (including Snapzy and Finder copies) and absolute local image paths are uploaded. Ordinary text and image-only clipboard data use Tern's native paste handling.

## Use

Use **`Cmd+V` for text and images**, locally or remotely. Copying alone never uploads. Local paste stays native; remote paste asynchronously checks for a local image file before either uploading it or invoking native paste.

You can also press `Cmd+Option+Shift+I` or run **Send clipboard image to the current remote** from the palette. The destination is captured when paste starts; switching focus during image upload does not redirect the attachment. If the pane closes, exits, changes host, or disconnects, insertion fails with the uploaded path shown in the error. A deferred native paste is cancelled if focus changes before clipboard inspection completes.

The dedicated chord is `cmd+alt+shift+i`, with command id `plugin.remote-image-paste.send-image`. On load/reload, the plugin maps the default `Cmd+V` to `plugin.remote-image-paste.paste` through Tern's runtime settings API: surface editors otherwise consume the default shortcut before command overrides. Unrelated custom bindings are preserved. To use a custom chord, bind that action in Preferences → Keyboard. Before disabling or uninstalling the plugin, remove its `Cmd+V` override there to restore native paste.

Delivery uses Tern's pane-specific input API with bracketed-paste markers and no carriage return. It does not require a remote `tern` executable or an image-inbox extension. The private cache avoids duplicate attachments from old inbox watchers. Other applications receive the remote path as a paste; submit the prompt yourself.

This is not a multi-file Finder uploader. [tern-file-paste](https://github.com/vokativ/tern-file-paste) covers that, and it does not handle an image-only clipboard.

## Limits

- macOS only. Other systems get a toast and do not upload.
- The Tern display name and the SSH target must already match, including port and key. A different SSH alias needs an SSH config `Host` entry under the Tern name.
- A successful input call is not an acknowledgement from the receiving application. Image attachment loading is the receiving application's responsibility.
- Reloading Tern during an upload can leave the file on the server without a pasted path.

## Paste routing fix (2026-10-12)

- Removed automatic paste interception after a custom `Cmd+V` handler exceeded Tern's 50 ms hook budget and was disabled until reload.
- Reconnected upload completion to the captured pane, without title-based targeting, command execution, or clipboard replacement.
- Cleared the old `Cmd+V` override through the running window's settings API. Editing `settings.json` or reloading plugins alone did not update that window's active keymap. When migrating an existing window, replace `keybinds` through `cx.settings:set` with the shortcut omitted; an empty action array disables a shortcut rather than restoring its default.
- Verified native text paste locally and remotely, native image attachment chips in local and remote omp, and explicit upload with file-digest verification and a focus change before insertion.

## File URL paste fix (2026-10-13)

- Restored paste-time upload for Snapzy/Finder file URLs. Native bitmap paste worked in the previous verification, but native file URL paste sent the Mac path to the remote host.
- Kept clipboard inspection and SSH asynchronous; local content uses native paste, and remote non-file content uses the focused surface's native paste action rather than terminal-only paste.
- Added explicit composer shortcut routing and bracketed-paste delivery to the captured pane. Uploads now use `~/.cache/remote-image-paste` instead of the shared image inbox.
- Verified real `Cmd+V` with a Snapzy file URL on `gpu-zhouy1`: attachment chips and matching SHA-256; focus-switch delivery without changing the local composer; local/remote text, local file and bitmap attachments, remote bitmap attachments, and terminal text without Enter. Test clipboard contents were restored.

