#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Arch Linux Custom Provisioning ==="

# 1. Auto-detect disk (favors nvme if present, otherwise sda/vda)
DEFAULT_DISK=$(lsblk -d -n -o NAME | grep -E 'nvme|sd|vd' | head -n 1)
DEFAULT_DISK="/dev/$DEFAULT_DISK"

read -p "Target Disk [$DEFAULT_DISK]: " DISK
DISK=${DISK:-$DEFAULT_DISK}

read -p "Hostname [arch]: " HOSTNAME
HOSTNAME=${HOSTNAME:-arch}

read -p "Username [daw]: " USERNAME
USERNAME=${USERNAME:-daw}

echo -n "LUKS Disk Encryption Password: "
read -s LUKS_PASSWORD
echo
echo -n "Root User Password: "
read -s ROOT_PASSWORD
echo
echo -n "User Password (for $USERNAME): "
read -s PASSWORD
echo

# 2. Stage temporary config files in /tmp so the repo stays clean and re-runnable
TMP_CONFIG="/tmp/user_configuration.json"
TMP_CREDS="/tmp/user_credentials.json"
trap 'rm -f "$TMP_CONFIG" "$TMP_CREDS"' EXIT

echo "Configuring templates..."
cp "$SCRIPT_DIR/user_configuration.json" "$TMP_CONFIG"
sed -i "s|@TARGET_DISK@|$DISK|g" "$TMP_CONFIG"
sed -i "s|@TARGET_HOSTNAME@|$HOSTNAME|g" "$TMP_CONFIG"

# Calculate exact bytes for BTRFS partition (Total Disk Size - 1 MiB Start Buffer - 1024 MiB Boot Partition - 1 MiB End Buffer)
TOTAL_BYTES=$(blockdev --getsize64 "$DISK")
BTRFS_SIZE=$((TOTAL_BYTES - 1075838976))

# Replace the placeholder AND remove the quotes so it becomes a valid integer in JSON
sed -i "s|\"@BTRFS_SIZE@\"|$BTRFS_SIZE|g" "$TMP_CONFIG"

# 3. Generate the exact credentials file archinstall expects
cat <<EOF > "$TMP_CREDS"
{
  "encryption_password": "$LUKS_PASSWORD",
  "!root-password": "$ROOT_PASSWORD",
  "users": [
    {
      "username": "$USERNAME",
      "!password": "$PASSWORD",
      "groups": [],
      "sudo": true
    }
  ]
}
EOF
chmod 600 "$TMP_CREDS"

# 4. Execute the silent, zero-touch installation
echo "Starting Archinstall... Grab a coffee."
archinstall --config "$TMP_CONFIG" --creds "$TMP_CREDS" --silent

echo "Installation complete! You can now reboot."
