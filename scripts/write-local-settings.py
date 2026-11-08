#!/usr/bin/env python3
"""Write non-secret per-machine settings. Values are escaped as Nix strings."""
import argparse
import json
import re
from pathlib import Path


def nix_string(value):
    return json.dumps(value, ensure_ascii=False).replace("${", r"\${")


def render(args):
    if args.user in {"root", "nobody"} or args.user.startswith("nixbld"):
        raise ValueError("Choose a personal login name, not a reserved system account")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", args.user):
        raise ValueError("Use a lowercase login name with letters, numbers, _ or -")
    if not re.fullmatch(r"[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?", args.hostname):
        raise ValueError("Use a hostname of 1-63 letters, numbers or hyphens")
    if not re.fullmatch(r"\d{2}\.\d{2}", args.state_version):
        raise ValueError("stateVersion must be YY.MM")
    extra_groups = getattr(args, "extra_groups", [])
    if any(not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*", group) for group in extra_groups):
        raise ValueError("Invalid supplementary group")
    groups = ["essentials", "desktop"] + args.apps
    if not set(groups) <= {"essentials", "desktop", "gaming", "development", "media"}:
        raise ValueError("Unknown application bundle")
    groups = list(dict.fromkeys(groups))
    unfree = bool(set(groups) & {"gaming", "development", "media"})
    fresh = getattr(args, "fresh", False)
    secure_boot = fresh or getattr(args, "secure_boot", False)
    fresh_settings = ""
    if fresh:
        fresh_settings += "  btrfsSnapshots = true; # Root/home snapshots with bounded retention.\n"
    if secure_boot:
        fresh_settings += "  secureBoot = true; # Signed Limine; keys are enrolled or reused by the installer.\n"
    return f'''{{
  # Private machine settings. Ignored by Git; preserved by update-system.
  # Do not put passwords, tokens or private keys here: Nix sources are public locally.
  machineModule = ./machine.nix;
  hostname = {nix_string(args.hostname)};
  stateVersion = {nix_string(args.state_version)}; # Never bump to update software.
  timeZone = {nix_string(args.timezone)};
  keyboardLayout = {nix_string(args.keyboard)};
  desktop = {nix_string(args.desktop)};
{fresh_settings}  # shell = "noctalia"; # Optional Hyprland override; defaults follow the desktop.
  allowUnfree = {str(unfree).lower()}; # Explicitly selected proprietary app bundles.
  updates = {{
    repository = {nix_string(args.repository)};
    branch = {nix_string(args.branch)};
    output = "local";
  }};
  users.{args.user} = {{
    description = {nix_string(args.user)};
    admin = true; # This account maintains the system.
    uid = {args.uid}; # Preserve file ownership.
    extraGroups = [ {" ".join(map(nix_string, extra_groups))} ]; # Preserve existing hardware/service access.
    appGroups = [ {" ".join(map(nix_string, groups))} ];
    homeStateVersion = {nix_string(args.state_version)};
    # extraPackages = [ "gimp" ]; # Image editing, if wanted.
  }};
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--user", required=True)
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--uid", type=int, default=1000)
    parser.add_argument("--state-version", default="26.05")
    parser.add_argument("--timezone", default="America/Toronto")
    parser.add_argument("--keyboard", default="us")
    parser.add_argument("--desktop", choices=["plasma", "niri", "hyprland"], default="plasma")
    parser.add_argument("--fresh", action="store_true", help="Enable Btrfs snapshots and signed Limine for a fresh installation")
    parser.add_argument("--secure-boot", action="store_true", help="Enable signed Limine using Secure Boot keys reused from another installation")
    parser.add_argument("--apps", nargs="*", default=[])
    parser.add_argument("--extra-groups", nargs="*", default=[])
    parser.add_argument("--repository", default="https://github.com/edwardnafornita/dotfiles.git")
    parser.add_argument("--branch", default="main")
    args = parser.parse_args()
    try:
        text = render(args)
        if args.destination:
            args.destination.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive creation: rerunning an installer never replaces preferences.
            with args.destination.open("x") as target:
                target.write(text)
        else:
            print(text, end="")
    except (ValueError, OSError) as error:
        parser.exit(1, f"Settings error: {error}\n")


if __name__ == "__main__":
    main()
