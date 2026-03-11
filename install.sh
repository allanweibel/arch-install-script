#!/bin/bash
set -e

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

# 2. Inject variables into the local JSON template using sed
echo "Configuring templates..."
sed -i "s|@TARGET_DISK@|$DISK|g" user_configuration.json
sed -i "s|@TARGET_HOSTNAME@|$HOSTNAME|g" user_configuration.json

# 3. Generate the exact credentials file archinstall expects
cat <<EOF > user_credentials.json
{
  "encryption_password": "$LUKS_PASSWORD",
  "!root_password": "$ROOT_PASSWORD",
  "users": [
    {
      "!password": "$PASSWORD",
      "groups": [],
      "sudo": true,
      "username": "$USERNAME"
    }
  ]
}
EOF

# 4. Execute the silent, zero-touch installation
echo "Starting Archinstall... Grab a coffee."
archinstall --config user_configuration.json --creds user_credentials.json --silent

echo "Installation complete! You can now reboot."