# A SteamOS Extension System and a Collection of SteamOS Extensions

This repo documents and provides an example set of extensions that utilize the 
`systemd-sysext` mechanism. This mechanism can be used to create permanent system
modifications that support filesystem overlays and automatically enabled systemd unit files.

## systemd-sysext

The mechanism this repo provides is little more than a supplement to systemd's built-in `systemd-sysext` mechanism. The primary addition this mechanism adds is a way to automatically load systemd units from installed `systemd-sysext` extensions, whereas normal extensions require users to manually enable any units they wish to use, which won't survive upgrades.

For documentation on how to build systemd-sysext extensions, please see here: https://www.freedesktop.org/software/systemd/man/latest/systemd-sysext.html

The rest of this README.md will focus on the specific differences needed to use this extension system wrapper.

## Built Images / End User

If you are an end user trying to understand or use any of these extensions, please find the built images and instructions to use them [here](https://github.com/MiningMarsh/steamos-extensions).

## How it Works

The `steamos-extension-loader.raw` extension provides two services: `steamos-extension-loader.service` and `steamos-extension-loader-installer.service`.

`steamos-extension-loader.service` and `steamos-extension-loader-installer.service` have two purposes:

1. They make sure that system updates do not uninstall their services and supporting files.
2. They install themselves as a boot service that loads any other installed extensions by making sure the appropriate unit files are enabled and running.

### Persistence

`steamos-extension-loader-installer.service` maintains its persistence in a fairly straightforward way. First, it checks `/etc/steamos-extension-loader`, `/etc/systemd/system/steamos-extension-loader.service` and `/etc/atomic-update.d/steamos-extension-loader.conf`, ensuring they have identical checksums to the files packaged in the extension. If they don't exist or have mismatching checksums, it copies the bundled file into those locations.

Secondly, `steamos-extension-loader-installer.service` enables and runs the `steamos-extension-loader.service` unit if it is not already enabled and active.

`steamos-extension-loader.service`, among other things, will start and enable `steamos-extension-loader-installer.service` and `systemd-sysext.service`, thus ensuring that `steamos-extension-loader.raw` updates get copied up into `/etc`.

Finally, the file placed in `/etc/atomic-update.d` ensures that none of the installed files are lost after a system update.

If persistence is ever lost, it should be enough to re-run the installation commands.

### Unit Files

`steamos-extension-loader.service`, in addition to helping with persistence, also ensures that services from other extensions are enabled and loaded. This is the advantage of `steamos-extension-loader.service`, as `systemd-sysext.service` provides no equivalent mechanism (at least as far as this author was able to determine; *please* correct me if I have overlooked anything here).

The algorithm it uses to enable units is very straightforward:

1. Any system unit file starting with `steamos-extension-` is passed to `systemctl preset`. After that, it checks if the unit is enabled. If it is enabled and it is not yet running, `steamos-extension-loader.service` starts the unit. This allows extension authors to decide which services and timers should be loaded by providing a correct systemd-preset file.

2. User unit files are treated differently. Systemd does not have an equivalent to systemd preset for user units; thus, every single unit is simply passed to `systemctl enable --global`, so that they will be loaded during logon. To control which units are running, you must ensure a correct install target. If you have a service fired by a timer that shouldn't run otherwise, omit the entire `[Install]` section in the unit file. User units also need to start with `steamos-extension-` to be considered for loading.

### System Updates

The SteamOS update mechanism does not like `systemd-sysext.service` to be running, as it creates a read-only overlayfs on `/usr`. To solve this problem, `systemd-sysext.service` unloads itself when `rauc.service` (the update service) is started. Unfortunately, `rauc.service` does not unload itself until reboot, which means all extensions are unloaded until reboot. Updates that occur during boot-up do not conflict with `systemd-sysext.service`, as only steam client updates can apply during boot-up.

## Extensions

Installing additional extensions is as easy as placing them in `/var/lib/extensions` and rebooting.

Extensions can be uninstalled by removing their extension file from `/var/lib/extensions`, and rebooting. It is safe to leave the loader installed even if all extensions are uninstalled, it just won't do anything.

The build script for these example extensions is included. It is designed to be run by the root user on a steam deck, allowing easier debugging: just clone this repository to any location and run `./build`. Extensions will be deposited in `/var/lib/extensions`.
