# Various shell scripts of mine

## cd_dvd_batch_copy.sh

Hassle-free copying of old CD/DVD backups back to backup disk(s). What does it do:
1. Wait for media being loaded to the source (optical) drive. Windows `wmic.exe` is used for this purpose.
1. Read the loaded medium volume serial# and volume name.
1. Create a unique subfolder in the target folder. The subfolder name is composed from the medium serial# and volume name.
1. `rsync` the medium contents to the <target folder>/<the medium's subfolder>.
1. Detect an existence of a checksum file on the source medium.
1. If there's no checksum file on the source medium, calculate the MD5 hashes from the source medium contents and store them in the target subfolder.
1. Check the target subfolder against the checksums from the checksum file.
1. If everything went OK thus far, eject the medium from the optical drive. (Windows shell functions called from PowerShell are used for this purpose.) Otherwise, repeat everything from step 4.
1. Repeat everything from step 1.

Effectively, all you have to do is replacing the CDs/DVDs in your optical drive's open tray and closing the tray. The script does everything else for you.
