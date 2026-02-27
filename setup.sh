#!/usr/bin/env bash
# Environment variables

set -euo pipefail
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ALL=false

bold=$(tput bold)
dim=$(tput dim)
reset=$(tput sgr0)
green=$(tput setaf 2)
blue=$(tput setaf 4)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
cyan=$(tput setaf 6)

# TODO: color the text also but with a fainter one: 
print_info() {
    echo "${bold}[${blue}Step${reset}${bold}] ${blue}==>${reset} ${dim}${blue}$1${reset}"
}
print_step() {
    echo "${bold}[${blue}Step${reset}${bold}] ${blue}==>${reset} ${dim}${blue}$1${reset}"
}
print_code() {
    echo "${bold}[${cyan}Code${reset}${bold}]   ${dim}${cyan}$1${reset}"
}
print_success() {
    echo "${bold}[${green}Success${reset}${bold}] ${green}✔${reset} ${dim}${green}$1${reset}"
}
print_error() {
    echo "${bold}[${red}Error${reset}${bold}]     ${red}✖${reset} ${dim}${red}$1${reset}"
}
print_warning() {
    echo "${bold}[${yellow}Warning${reset}${bold}]   ${yellow}⚠${reset} ${dim}${yellow}$1${reset}"
}

ask_run() {
    local
}
ask_run() {
    local message="$1"

    # If runall was already selected, skip asking
    if [ "$RUN_ALL" = true ]; then
        return 0
    fi

    while true; do
        read -rp "$message (y/n/runall): " choice
        case "$choice" in
            y|Y)
                return 0
                ;;
            n|N)
                return 1
                ;;
            runall)
                RUN_ALL=true
                return 0
                ;;
            *)
                echo "Please answer y, n, or runall."
                ;;
        esac
    done
}


print_step "Starting full installation..."

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

print_step "Configuring locale"

sudo tee /etc/locale.conf >/dev/null <<EOF
LANG=en_US.UTF-8
LC_ADDRESS=fi_FI.UTF-8
LC_IDENTIFICATION=fi_FI.UTF-8
LC_MEASUREMENT=fi_FI.UTF-8
LC_MONETARY=fi_FI.UTF-8
LC_NAME=fi_FI.UTF-8
LC_NUMERIC=fi_FI.UTF-8
LC_PAPER=fi_FI.UTF-8
LC_TELEPHONE=fi_FI.UTF-8
LC_TIME=fi_FI.UTF-8
EOF

print_success "Locale configured"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

print_step "Installing reflector: a mirrorlist generator"

sudo pacman -S --noconfirm reflector rsync curl

# TODO: check if mirrorlist has already been generated
print_step "Generating fastest mirrorlists for Finland"

sudo reflector --verbose --country 'Finland' -l 5 --sort rate --save /etc/pacman.d/mirrorlist

print_success "Mirrorlist generated"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

print_step "Installing base packages"

sudo pacman -Syu --noconfirm

sudo pacman -S --needed --noconfirm \
  base-devel git openssh yadm

print_success "Base packages installed"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

print_step "Creating user directories"

mkdir -p \
  ~/.cache ~/.config ~/.local ~/.ssh \
  ~/Backup ~/Desktop ~/Documents ~/Downloads \
  ~/Music ~/Pictures ~/Projects ~/Public \
  ~/Templates ~/Videos

print_success "Directories created"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

print_step "Installing yay: AUR helper"

if ! command -v yay &> /dev/null; then
    print_step "Installing yay AUR helper..."
    sudo pacman -S --needed --noconfirm base-devel
    git clone https://aur.archlinux.org/yay.git ~/.cache/buildyay
    cd buildyay
    makepkg -o
    makepkg -se
    makepkg -i --noconfirm
    cd "$SCRIPT_DIR"
    rm -rf ~/.cache/buildyay
fi

print_success "Yay installed!"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

print_step "Installing dependencies from depends.txt"

DEP_FILE="$SCRIPT_DIR/depends.txt"

if [ ! -f "$DEP_FILE" ]; then
    print_error "depends.txt file not found."
    exit 1
fi

# Read non-empty, non-comment lines
mapfile -t PACKAGES < <(grep -vE '^\s*#|^\s*$' "$DEP_FILE" | tr -d "’“”")

for pkg in "${PACKAGES[@]}"; do
  if ! yay -S --needed --noconfirm "$pkg"; then
    print_warning "Failed to install $pkg"
  fi
done



# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––-----

print_step "Adding i2c group if missing" 
sudo groupadd i2c 2>/dev/null || true  

print_step "Adding Add user to required groups"  
sudo usermod -aG video,i2c,input "$(whoami)"

print_step "Load i2c-dev module at boot"
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf  
  
print_step "Enable ydotool service (user service)"  
systemctl --user enable ydotool --now  
  
print_step "Enable bluetooth service"
sudo systemctl enable bluetooth --now

print_step "Set gnome font and dark theme"  
gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'  
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'  
  
print_step "Set KDE dark widget style"  
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Darkly

print_success "Groups, services, permissions, etc successfully configured."


# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

# Copy the ssh securely from old machine (has to have sshd running)
# sudo systemctl start sshd
print_step "Let's copy the ssh key from the old machine (sudo systemctl start sshd):"
print_code "scp OLD_USERNAME@OLD_MACHINE_IP:~/.ssh/id_ed25519 ~/.ssh/"

read -rp "Old machine username: " old_username
read -rp "Old machine IP: " old_ip_address

scp "${old_username}@${old_ip_address}:~/.ssh/id_ed25519" ~/.ssh/
scp "${old_username}@${old_ip_address}:~/.ssh/id_ed25519".pub ~/.ssh/

print_success "SSH key copied successfully."
print_step "Setting up correct permissions"

chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

print_success "Correct permissions set"

print_success "SSH key copied and permissions set"

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

echo "Configuring git..."

git config --global user.name "maataan"
git config --global user.email "maataan@proton.me"

echo "Cloning yadm dotfiles..."
yadm clone https://github.com/maataan/dotfiles.git

print_success "Git configured and dotfiles cloned."

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--

sudo pacman -Suy --noconfirm

# ––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––--