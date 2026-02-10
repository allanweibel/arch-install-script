#!/bin/bash

# ==========================================
#  ARCH LINUX UNIVERSAL INSTALLER (VM + T480)
#  Features: Btrfs, LUKS, ZRAM, Timeshift, Grub-Btrfs
# ==========================================

# --- 1. INTERACTIVE CONFIGURATION ---
clear
echo "=== ARCH LINUX INSTALLATION SETUP ==="

# Auto-detect disk (favors nvme if present, otherwise sda/vda)
DEFAULT_DISK=$(lsblk -d -n -o NAME | grep -E 'nvme|sd|vd' | head -n 1)
DEFAULT_DISK="/dev/$DEFAULT_DISK"

read -p "Target Disk [$DEFAULT_DISK]: " DISK
DISK=${DISK:-$DEFAULT_DISK}

read -p "Hostname [arch-golden]: " HOSTNAME
HOSTNAME=${HOSTNAME:-arch-golden}

read -p "Username [daw]: " USERNAME
USERNAME=${USERNAME:-daw}

echo -n "User Password: "
read -s PASSWORD
echo
echo -n "Root Password: "
read -s ROOT_PASSWORD
echo

read -p "Timezone [Europe/Zurich]: " TIMEZONE
TIMEZONE=${TIMEZONE:-Europe/Zurich}

read -p "Keymap [de_CH-latin1]: " KEYMAP
KEYMAP=${KEYMAP:-de_CH-latin1}

echo "-------------------------------------"
echo "INSTALLING TO: $DISK"
echo "HOSTNAME:      $HOSTNAME"
echo "USER:          $USERNAME"
echo "-------------------------------------"
echo "!!! WARNING: ALL DATA ON $DISK WILL BE DESTROYED !!!"
echo "Press Ctrl+C to cancel. Starting in 5 seconds..."
sleep 5

# --- 1.5. PRE-FLIGHT CHECKS ---
echo ">> [0/8] synchronizing clock..."
timedatectl set-ntp true
# Wait a moment for sync (optional but safe)
sleep 2

# --- 2. PARTITIONING ---
echo ">> [1/8] Partitioning $DISK..."
sgdisk -Z $DISK # Zap all data
# Partition 1: EFI (512M)
sgdisk -n 1:0:+512M -t 1:ef00 $DISK
# Partition 2: Main (Rest of disk)
sgdisk -n 2:0:0 -t 2:8300 $DISK

partprobe $DISK
sleep 2

# Handle Partition Naming (NVMe vs SATA)
if [[ $DISK == *"nvme"* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

# --- 3. ENCRYPTION (LUKS) ---
echo ">> [2/8] Encrypting $PART2..."
echo -n "$PASSWORD" | cryptsetup luksFormat $PART2 -
echo -n "$PASSWORD" | cryptsetup open $PART2 main -

# --- 4. FORMATTING & SUBVOLUMES ---
echo ">> [3/8] Formatting Btrfs & Subvolumes..."
mkfs.fat -F32 $PART1
mkfs.btrfs -f /dev/mapper/main

mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
umount /mnt

# --- 5. MOUNTING ---
echo ">> [4/8] Mounting..."
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mkdir -p /mnt/{home,boot,var/log,.snapshots}
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@snapshots /dev/mapper/main /mnt/.snapshots
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@var_log /dev/mapper/main /mnt/var/log
mount $PART1 /mnt/boot

# --- 6. PACSTRAP (Base Install) ---
echo ">> [5/8] Installing Base Packages..."
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers \
    btrfs-progs grub efibootmgr grub-btrfs \
    networkmanager network-manager-applet \
    openssh sudo neovim git mtools \
    iptables-nft ipset firewalld reflector acpid \
    intel-ucode \
    man-db man-pages texinfo bluez bluez-utils \
    pipewire pipewire-pulse pipewire-jack wireplumber alsa-utils \
    zram-generator timeshift ly

# --- 7. CONFIGURATION (Fstab & Chroot) ---
echo ">> [6/8] Generating Fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ">> [7/8] Configuring System..."
arch-chroot /mnt /bin/bash <<EOF

# Time & Lang
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Network
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Users
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- ZRAM CONFIGURATION ---
# Create the config file directly
cat <<ZRAM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM

# --- TIMESHIFT & GRUB-BTRFS FIX ---
# The guide asks to change ExecStart to use '-t' (monitor timeshift)
# We override the systemd service file by copying it to /etc and editing it
mkdir -p /etc/systemd/system/grub-btrfsd.service.d/
# Alternatively, we can just edit the installed file for simplicity in a script:
sed -i 's|/.snapshots|-t|g' /usr/lib/systemd/system/grub-btrfsd.service
# Force systemd to see the change (though effectively handled on reboot)
systemctl daemon-reload

# --- MKINITCPIO ---
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# --- GRUB ---
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
UUID=\$(blkid -s UUID -o value $PART2)
sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\".*\"|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\$UUID:main root=/dev/mapper/main\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# --- ENABLE SERVICES ---
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sshd
systemctl enable ly
systemctl enable firewalld
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable acpid
systemctl enable grub-btrfsd

EOF

echo ">> [8/8] Installation Complete!"
echo "Rebooting in 5 seconds..."
sleep 5
# reboot  <-- Uncomment this if you want auto-reboot, otherwise manual