# Arch Linux Zero-Touch Provisioning

**1. Verify internet connection:**
\`\`\`bash
ping -c 2 archlinux.org
\`\`\`

**2. Install Git (Silently):**
\`\`\`bash
pacman -Sy git --noconfirm
\`\`\`

**3. Download and Run:**
\`\`\`bash
git clone <https://github.com/allanweibel/arch-install-script.git> && cd arch-install-script && bash install.sh
\`\`\`
