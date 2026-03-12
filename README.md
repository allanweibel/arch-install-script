Verify internet first

```
ping -c 2 archlinux.org
```

Check if git is already installed

```
sudo pacman -Sy git
```

Download the script

```
git clone https://github.com/allanweibel/arch-install-script.git
```

Navigate to directory

```
cd arch-install-script
```

Set permission

```
chmod +x install.sh
```

Run it

```
./install.sh
```
