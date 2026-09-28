# Change settings here

`settings/hosts/nixos.nix` selects the existing machine. The installer generates
`settings/local/default.nix` on other computers. It is not committed and survives
`git pull`. Both files use the same typed options from `options.nix`; a typo or
unsupported desktop fails evaluation instead of silently doing nothing.

## A complete small profile

```nix
{
  machineModule = ./machine.nix; # Local hardware/boot module, never someone else's UUIDs.
  hostname = "family-pc";
  stateVersion = "26.05"; # Version at first install; leave it alone during upgrades.
  timeZone = "America/Toronto";
  desktop = "plasma";
  browser = "firefox";
  allowUnfree = true; # Accept licenses for the gaming bundle chosen below.
  users.alex = {
    description = "Alex";
    uid = 1000; # Keep existing UIDs on existing systems.
    admin = true; # Required for system updates using sudo.
    appGroups = [ "essentials" "desktop" "gaming" ];
    extraPackages = [ "gimp" ]; # Image editing for this account.
    homeStateVersion = "26.05";
  };
  users.sam = {
    description = "Sam";
    uid = 1001;
    appGroups = [ "essentials" "desktop" ];
  };
}
```

Add accounts by adding entries. Run `apply-system`, reboot, then set each new
account's password with `sudo passwd NAME`. Do not rename an existing account as
if it were a theme setting: home-directory/file ownership migration is separate.
Omitting an old user does not delete their home or necessarily delete their account
because mutable users preserve passwords; removing accounts is an explicit
administrator operation. Keep at least one administrator. On a shared PC only
admin accounts receive the update commands/shortcuts; keep one primary checkout
for maintenance, or give other administrators their own identical local settings.

## Applications

Edit `applications.nix` to change the shared bundles. Each direct package has an
inline explanation of why it is included. Select bundles per account:

| Bundle | Purpose | System effects |
| --- | --- | --- |
| `essentials` | Editor, Git/GitHub, downloads, process/directory tools | None |
| `desktop` | Office suite, media player, graphical editor | None |
| `gaming` | Game launchers, Wine tools, mods and voice/chat | Steam, 32-bit graphics, GameMode, Gamescope and controller rules |
| `development` | .NET SDK, Rider, VS Code and development clients | direnv in that account; **no** Docker or PostgreSQL daemon |
| `media` | Spotify | None |

`extraPackages` accepts nixpkgs attribute names such as `gimp`, `obs-studio` or
`kdePackages.kdenlive`. Add a comment explaining your need. These local additions
survive shared bundle changes. To remove individual shared packages for one
account, omit that bundle and list the desired applications in `extraPackages`.
The system gaming integration is selected by the `gaming` bundle, not by guessing
from extra package names. Proprietary packages require `allowUnfree = true`.

The browser is a separate machine setting (`firefox` or `helium`) because the
compositor shortcuts and system browser integration must agree. Terminals and file
managers follow the session: Konsole/Dolphin with Plasma, Alacritty/Thunar with the
compositors. UI changes within these apps remain user-controlled unless explicitly
managed by Home Manager.

## Defaults and feature rationale

| Setting | Default | Why |
| --- | --- | --- |
| `desktop` | `"plasma"` | Full desktop with graphical settings and familiar workflows |
| `shell` | follows desktop | Plasma: `"none"`; Niri: `"noctalia"`; Hyprland: `"caelestia"` or explicit `"noctalia"` |
| `browser` | `"firefox"` | Mainstream browser maintained in stable nixpkgs |
| `printing` | `true` | Printers work through CUPS; mDNS discovery opens UDP 5353 locally |
| `bluetooth` | `true` | Headphones, mice and controllers |
| `flatpak` | `true` | GUI-managed applications outside the curated bundles |
| `allowUnfree` | `false` | Proprietary licenses require an explicit choice |
| `xboxControllers` | `false` | Extra Xbox drivers only on machines needing them |
| `powerTuning` | `false` | Use power-profiles-daemon on generic machines; tuned is an explicit alternative |
| `sddmAstronaut` | `false` | Stock login screen needs fewer theme dependencies |
| `metaTapLauncher` | `false` | Opt-in tap-Super launcher in compositor sessions; Plasma keeps its own shortcut |
| `niriOutputs` | empty | Automatically discover each computer's monitors |
| `hyprlandMonitors` | automatic | No hardcoded connectors/resolutions on friends' PCs |
| `users.NAME.bash` | `"standard"` | Predictable shell; Edi explicitly selects `"ctt"` |

NetworkManager supplies network setup. PipeWire/WirePlumber supply desktop audio.
Polkit supplies graphical authorization, and UPower reports battery information.
Fonts provide broad language coverage. Automatic `nh` cleanup retains at least
five generations and generations from the last seven days. These baseline choices
are documented next to their implementation in `modules/`.

`settings/defaults.nix` can define shared policy with `lib.mkDefault`:

```nix
{ lib, ... }: {
  timeZone = lib.mkDefault "Europe/Berlin";
  printing = lib.mkDefault false;
}
```

Normal definitions in a host's settings override these defaults. The schema's
own defaults have lower priority. Do not put duplicate normal definitions in both
places unless you deliberately want Nix to report a conflict.

## Update source

`updates.repository`, `updates.branch`, `updates.checkout` (relative to home) and
`updates.output` select the updater source. The default repository is this repo,
the branch is `main`, and the checkout is `dotfiles`. Friends use output `local`;
Edi uses `edi-nixos`. A fork must change both Git's origin and these settings; run
`apply-system` to install the new updater before asking it to fetch another source.
Updating a system trusts that repository's code with administrator privileges.
Only distribute branches you review and test.

With a `path:` source and local settings, the flake exposes `local` and that
computer's hostname as aliases of the same system. No personal profile is exposed.
Git sources omit ignored local settings: without them, only the explicitly named
`edi-nixos` profile exists. Requests for `local` or the generic hostname `nixos`
then fail instead of falling back to Edi's disks. Always use `path:` for friends.
The update commands already do this. The optional `nh` utility has no implicit
flake setting; pass its source explicitly or use `apply-system`.

For Hyprland with Noctalia, set both values in your machine settings:

```nix
desktop = "hyprland";
shell = "noctalia";
```

Hyprland defaults to Caelestia when `shell` is omitted. Niri supports Noctalia;
Plasma uses its own panel and lock screen. Remove an explicit shell override when
switching back to Plasma. Configure shell appearance in `shells/`; compositor
shortcuts and layout remain in `desktops/`. Only the selected shell and its
authentication agent are enabled.

SDDM follows the upstream greeter defaults (Wayland for Plasma, X11 for the
compositor profiles). An adopted machine's explicit `sddm.wayland.enable` is
preserved. The existing Niri machine continues to use its X11 greeter.
