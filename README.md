# Bulwark

A self-binding website blocker for macOS. Built as a commitment device against
compulsive use: **adding a site is instant; getting one back is deliberately hard.**

Removing a site (or weakening the tool) requires *either* a long cooldown
(default 48h) *or* an accountability partner's passphrase that you never learn.
The block is enforced by a root watchdog that self-heals any tampering within
seconds.

> **Read this honestly:** on a Mac where *you* have the admin password, nothing
> is 100% unbypassable — a determined person can boot into Recovery. Bulwark's
> job is to make bypass slow, effortful, and visible so a *moment of weakness*
> can't beat it. The lasting fix is friction + a human in the loop, not an
> unbeatable lock. See [DESIGN.md](DESIGN.md) for the full threat model.

## How it works

Defense in depth, all enforced by a root LaunchDaemon (`bulwarkd`):

| Layer | What it does |
|---|---|
| `/etc/hosts` sinkhole | Points blocked domains (+ `www.`) at `0.0.0.0` for every app |
| `pf` firewall anchor | Blocks known DNS-over-HTTPS/TLS resolvers so browsers can't DNS around the hosts file |
| `chflags schg` | Marks every managed file OS-immutable |
| watchdog daemon | Re-applies all of the above on a 15s loop; `KeepAlive` relaunches it if killed |
| removal gate | add = instant · remove = 48h cooldown **or** partner passphrase |

## Install

```bash
git clone <this repo> && cd bulwark
sudo ./install/install.sh
```

Then:

```bash
# 1. Have your accountability partner set the passphrase (don't watch):
sudo bulwark set-passphrase

# 2. Block sites (takes effect immediately):
sudo bulwark add pornhub.com xvideos.com

# 3. Anytime:
bulwark status
```

## Usage

```
bulwark status                     show blocked sites and pending removals
sudo bulwark add <site>...         block site(s) immediately
sudo bulwark remove <site>         queue removal — stays blocked for the cooldown
sudo bulwark remove <site> --now   remove now (requires partner passphrase)
sudo bulwark cancel <site>         change of heart: cancel a pending removal
sudo bulwark set-passphrase        set/change the partner passphrase
sudo bulwark set-cooldown <hours>  raise freely; lowering needs the passphrase
sudo bulwark enforce               force re-apply enforcement now
```

## Development

```bash
swift build        # build CLI + daemon
swift test         # run the suite
```

Paths are overridable via `BULWARK_HOME` / `BULWARK_HOSTS` / `BULWARK_PF_ANCHOR`
so you can exercise the real binaries against a sandbox without root:

```bash
export BULWARK_HOME=/tmp/bw/home BULWARK_HOSTS=/tmp/bw/hosts BULWARK_PF_ANCHOR=/tmp/bw/pf
.build/debug/bulwark add example.com && .build/debug/bulwark status
```

## Roadmap

See [DESIGN.md](DESIGN.md#roadmap). The big one: a **Network Extension content
filter** (`NEFilterDataProvider`) — it filters on-device, so it is immune to
DoH/DoT and far harder to remove than hosts/pf. That's the path to genuinely
strong enforcement, and it needs the Apple Developer signing you have.
