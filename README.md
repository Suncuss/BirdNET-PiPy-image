# BirdNET-PiPy Image

A flashable Raspberry Pi OS image for [BirdNET-PiPy](https://github.com/Suncuss/BirdNET-PiPy),
meant to be installable straight from Raspberry Pi Imager.

**Status: early.** There is no image to download yet. This repo holds the plan
and the test harness; the image build comes next.

## How it will work

1. The image is Raspberry Pi OS Lite (64-bit) plus what BirdNET-PiPy needs up
   front. The app itself isn't installed into the image, because the user
   account doesn't exist until first boot: Raspberry Pi OS creates it from the
   settings you enter in Imager.
2. On first boot, once cloud-init has created that account, a one-time service
   runs the app's own installer:

   ```bash
   install.sh --unattended --user <the Imager user>
   ```

   That command is the whole contract between this repo and the app repo. All
   install logic stays in the app repo and is tested there, so a change to the
   installer can't silently break the image.
3. Once installed, the station updates itself in-app like any other install.
   The image only needs rebuilding when Raspberry Pi OS ships a new base.
4. Images are published as GitHub Release assets here, with a repository JSON
   that Imager can load (App Options → Content Repository, or
   `rpi-imager --repo <url>`). Applying for the official Imager list comes after
   a few releases have held up.

The `--unattended` and `--user` installer options land in the app's next
release; the image needs an app version that has them.

## Versioning

Tag image releases **in this repo only**. The Home Assistant add-on finds new
app versions by parsing tag names in the app repo, and a tag like
`image-2026.10` there would read as app version 2026.10.

## Testing

| Layer | What | Where |
|---|---|---|
| 1 | Inspect the built image: files, enabled units, no baked-in secrets | Any Linux host |
| 2 | Run the image's root filesystem in the app's install-test container | Docker |
| 3 | Boot the image in a VM with Imager-style first-boot settings | `test/vm/` |
| 4 | Real hardware: Pi 4B and Zero 2W, on spare SD cards | Bench |

### VM test (layer 3)

Runs on an arm64 host with hardware acceleration: KVM on a Pi 5, HVF on Apple
Silicon.

```bash
test/vm/build-kernel.sh                  # once: generic arm64 kernel + initrd
ssh-keygen -t ed25519 -N '' -f vm_key    # throwaway key for the VM
test/vm/seed.sh my.img vm_key.pub        # Imager-style user, SSH key, hostname
test/vm/boot.sh my.img --background      # console log: my.img.console.log
ssh -i vm_key -p 2222 birder@127.0.0.1
```

Needs QEMU, mtools, Docker and an `openssl` that supports `passwd -6`.
On macOS: `brew install qemu mtools openssl@3`, with Docker from colima.

What the VM can't show, so real hardware covers it: Pi firmware and
`config.txt`, the first-boot root partition resize (Raspberry Pi OS does it in
its own initramfs, which the VM doesn't use), zram swap, EEPROM updates and
audio devices.

Verified on 2026-09-30 with Raspberry Pi OS Lite 2026-09-15 (Trixie) on a Pi 5:
first boot takes about 40 seconds, and the Imager user always gets UID 1000.
Raspberry Pi OS ships a locked placeholder `pi` account at UID 1000 and renames
it to the Imager user (`userconf-pi`), which matches what the app's pre-built
images expect.

## License

[CC BY-NC-SA 4.0](LICENSE), the same as BirdNET-PiPy. Images built here also
contain Raspberry Pi OS, which is under its own licenses.
