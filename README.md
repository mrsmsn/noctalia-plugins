# noctalia-plugins

Personal [Noctalia](https://github.com/noctalia-dev/noctalia) plugins.

| Plugin | Description |
| --- | --- |
| [kdeconnect-reply](kdeconnect-reply/) | Reply to KDE Connect notifications (LINE, SMS, …) from a native panel |

## Install

Add this repository as a plugin source, then enable a plugin:

```sh
noctalia msg plugins source add mrsmsn git https://github.com/mrsmsn/noctalia-plugins
noctalia msg plugins enable mrsmsn/kdeconnect-reply
```

Panels register at startup, so restart Noctalia after the first enable.

For local development, clone anywhere and symlink the plugin directory into
`~/.local/share/noctalia/plugins/` (auto-discovered as the built-in local
source), or register the checkout as a `path` source.
