# KDE Connect Reply

Reply to your phone's replyable notifications (LINE, SMS, WhatsApp, …) from a
native Noctalia panel. Pick a conversation, type, press Enter.

Noctalia advertises the `inline-reply` notification capability but the reply
never reaches kdeconnectd (the notification is closed by the time the action is
invoked), so this panel bypasses the notification UI entirely: kdeconnectd
exposes every phone notification as a DBus object with a `replyId` and a
`sendReply(text)` method, and the panel drives those directly.

## Requirements

- `kdeconnect` (kdeconnectd running, phone paired, notification sync on)
- `busctl` (systemd) and `jq`

## Usage

Open the panel:

```sh
noctalia msg panel-toggle mrsmsn/kdeconnect-reply:reply
```

Bind it to a key, e.g. niri:

```kdl
Super+R { spawn-sh "noctalia msg panel-toggle mrsmsn/kdeconnect-reply:reply"; }
```

## Notes

- Only notifications the phone app marks as replyable show up (`replyId` set).
- Without this plugin you can still reply via the stock Qt dialog: call the
  notification object's `reply()` method over DBus — see the source for paths.
