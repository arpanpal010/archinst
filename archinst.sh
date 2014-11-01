#!/bin/bash
#
#Author: Arpan Pal
#Email: arpan.pal010@gmail.com
#=======================================================================
#TODO
#=======================================================================
#add --needed --noconfirm to pacman after finalized
#move grub install to own function + debug
#started adding device exclusive settings
#setup binds for custom mounts
#fix networker to start autmatically if no internet - make it flexible
#add UEFI support
#=======================================================================
#Description:
#=======================================================================
#Semi-interactive install script for Arch Linux.
#A combination of tasks from both the beginners and advanced install tasks for installing archlinux on x86 or x86_64 devices.
#however, post installation tasks are almost similar in all architectures, so needs a bit of knowledge to customize the script if used in other architecturs.
#
#The procedure of installing archlinux comprises of a total 4 stages to setup upto the administrator account, and
#another one to setup the user account specific settings. Namely these stages and the steps they perform are described below.
#
#pre-boot
#-----------------------------------------------------------------------
#	download iso fron any of the mirrors
#	verify iso with the signature file
#	write iso to USB (Not safely implemented yet, use `dd if=/path/to/img of=/dev/sdX bs=8M`)
#	boot device with said USB
#
#pre-installation: (recheck device config like mounts, grub-device etc before start)
#-----------------------------------------------------------------------
#	set time to localtime as set in $time_zone/$time_subzone
#	check if boot type is UEFI, the script does not work with UEFI
#	update /etc/pacman.d/mirrorlist using rankmirrors
#	mount block devices (as listed in config)
#	run pacstrap
#	generate /etc/fstab
#	chroot
#	run post-installation (see next step)
#	unmount block devices and reboot
#
#post-installation: (executed inside chroot)
#-----------------------------------------------------------------------
#	set hostname
#	set root password
#	generate locales
#	set time
#	generate initramfs
#	install bootloader grub2 + scan for other OSs to generate boot configuration
#	create administrator (not root)
#	set administrator password
#	give sudo privilege to the group wheel
#	exit chroot
#
#system configuration: (done after logging in with administrator account, needs sudo)
#-----------------------------------------------------------------------
#	enable multilib
#	setup firewall
#	start services (as set in config)
#	run initial rkhunter scan
#	run initial lm_sensors scan
#	install user packages
#	start user services (as set in config)
#
#user configuration: (run with user accounts, without sudo)
#-----------------------------------------------------------------------
#	generate private-public keypairs for ssh
#	install yaourt
#	install AUR packages
#	setup user configurations (git + linkthedots.sh)
#
#=======================================================================
#Requirements
#=======================================================================
#needs wget, grep, ls included in the archlinux iso that can be downloaded with this scripts
#pre-install network is setup manually, use wicd-curses (or wicd-gtk after installing wm) everywhere else
#
#=======================================================================
#Functions:
#=======================================================================
#get iso from specified mirror
#verify iso
#rank repository mirrors by their speed (rankmirrors)
#mount block devices
#generate locales
#set time
#setup basic firewall (iptables)
#install bootloader (grub2)
#install packageges
#start services
#generate ssh private/public keys
#
#=======================================================================
#configuration options - specify default values below
#=======================================================================
#these are default or common values, to set values according too device
#setup devices according to their hostname in devices section

dry_run=true; #script doesnt do anything, but says it does.
debug=true; #ask before every step #not yet implemented
#source of script
scriptsrc="https://raw.githubusercontent.com/arpanpal010/archinst/master/archinst.sh"
#-----------------------------------------------------------------------
#stage=preboot - writing the usb device
#-----------------------------------------------------------------------
#arch version - latest
arch_mirror="http://mirror.cse.iitk.ac.in/archlinux/iso/latest/"; #indian mirror for iso download #replace with own
arch_isonamereg="archlinux-*-dual.iso";

verify_iso=true; #verify iso with signature after download

arch_iso=""; #overrides iso download #set only if iso already downloaded.
arch_sig=""; #signature of iso...must be of same release for verification

#set usb device
DEV_USB=""; #recheck /dev/sdb
block_size="8M";
#-----------------------------------------------------------------------
#stage=preinst
#-----------------------------------------------------------------------
#kb_layout="us"; #keyboard layout

#internet - wired - dhcp - wifi -  used by networker() - better use wicd-curses in all cases except preinstallation
#net_interface="";
#net_connection_type=""; # "wired" / "wifi"
#ip_type=""; # "dhcp" or "static"

#static addresses - leave blank if dhcp
#if [ "$ip_type" == "static" ];
#then
#	net_ip="" ;				#e.g "192.168.1.101";
#	net_mask="";			#e.g "/24"; #CIDR #mind the slash
#	net_broadcast="";		#e.g "192.168.1.255";
#	net_gateway="";			#e.g 192.168.1.1";
#	net_nameserver="";		#e.g 192.168.1.1"; #DNS server
#fi;

#-----------------------------------------------------------------------
#mounts
#-----------------------------------------------------------------------
#required
mount_root="";  mountpoint_root="/mnt";         fstype_root="ext4"; format_root=true;
#OPTIONAL
mount_swap="";
mount_home="";  mountpoint_home="/mnt/home";    fstype_home="ext4"; format_home=true;
mount_boot="";  mountpoint_boot="/mnt/boot";    fstype_boot="fat";  format_boot=false;
mount_var="";   mountpoint_var="/mnt/var";      fstype_var="ext4";  format_var=true;
mount_etc="";   mountpoint_etc="/mnt/etc";      fstype_etc="ext4";  format_etc=true;
mount_usr="";   mountpoint_usr="/mnt/usr";      fstype_usr="ext4";  format_usr=true;

#grub install device
grub_device="";

#packages to install while pacstrap
strap_pkgs="base base-devel grub os-prober wicd"; #dialog wpa_supplicant if using wifi-menu/netctl/networkmanager later
#-----------------------------------------------------------------------
#stage=postinst
#-----------------------------------------------------------------------
#locales
gen_locales=(
	"en_IN.UTF-8" 	#native locale, replace with own if not in below
	"en_US.UTF-8"
	"en_GB.UTF-8"
);
#systime 			#replace with own
time_zone="Asia";
time_subzone="Kolkata";

#user add
user_grtype="users"; #belonging in group
user_gradd="wheel,storage,power,games"; #added to group
user_name="arch";
user_shell="/bin/bash";
#-----------------------------------------------------------------------
#stage=sysmgmt
#-----------------------------------------------------------------------
#pacman -Qqe to list all currently installed packages #just -Q to list all packages + dependencies
#system packages - install at post installation - common for all installs
install_pkgs_system=(
#	"linux-lts" 				#long-term-supported kernel #breaks much less
	"wget lsof bc ntp hdparm"	#misc tools web, calculator, time server etc
	"openssh sshfs" 			#ssh server, sshfs or fuse itself, however only this one needed mostly
	"p7zip rkhunter dosfstools" #rkhunter = rootkit checker
#	"mlocate"					#mlocate = file locator
	"acpid cpupower lm_sensors" #cpuscaling and powermon #view sensor data lm_sensors
	"alsa-utils alsa-plugins" 	#alsa
    "vim-minimal"				#text editor
	"htop"						#system monitor
	"bash-completion"			#command-completion for bash
	"git"						#vcs
);

#services to start after systemconf
services_system=("cpupower.service" "sshd.service"); #wicd should be already running

#optional package groups - installed by user
#-----------------------------------------------------------------------
						#xorg-server + apps + utils + xterm
opt_pkgs_x11="xorg-server xorg-apps xorg-xinit xorg-server-utils xterm xclip";
						#graphics drivers #intel drivers - now included in mesa-> intel-dri lib32-intel-dri #2014-10-03
opt_pkgs_gfx_intel="xf86-video-intel mesa-dri lib32-mesa-dri mesa-vdpau lib32-mesa-vdpau";
						#nvidia card + intel dri (laptop)
opt_pkgs_gfx_nvidia="bumblebee bbswitch primus virtualgl lib32-primus lib32-virtualgl nvidia lib32-nvidia-utils"
						#fonts
opt_pkgs_font="ttf-dejavu ttf-inconsolata terminus-font ttf-liberation";
						#sound server: pulseaudio+alsa
optional_pkgs_pulseaudio="pulseaudio paprefs pavucontrol pulseaudio-alsa lib32-libpulse lib32-alsa-plugins";
						#vbox #enable dkms.service from systemctl and modprobe vboxdrv before loading guests
opt_pkgs_vbox="virtualbox qt4 virtualbox-host-dkms linux-headers virtualbox-guest-iso";
						#office suite - libreoffice
opt_pkgs_libreoffice="libreoffice-fresh libreoffice-fresh-en-GB libreoffice-still-gnome";
						#XMPP+irc - pidgin #suspend needs a separate systemd unit https://wiki.archlinux.org/index.php/Pidgin
opt_pkgs_pidgin="pidgin pidgin-otr pidgin-encryption"
						#django stack
opt_pkgs_djangoserver="nginx uwsgi uwsgi-plugin-python python-django"; #depends python3

#common packages - use this as a basic template when installing pacckages, either extend it, or rewrite it when setting own preset.
install_pkgs_user=( #if the device needs specific packages or drivers, specify in devices giving it a seperate name
	"gksu"							#gui sudo
	"$opt_pkgs_x11"					#display server : x
	"awesome"						#wm + themes
	"lxappearance numix-themes elementary-icon-theme xcursor-vanilla-dmz" #GTKthemes/icons/cursor
	"gpointing-device-settings"		#mouse
	"wicd-gtk"						#gui networks
	"$opt_pkgs_font"				#fonts
	"$optional_pkgs_pulseaudio"		#sound
	"rxvt-unicode"					#terminal #remove if use only xterm
	"gnome-disk-utility"			#disk util gui
	"pcmanfm xarchiver udisks" 		#files + automount + archive gvfs
	"zip unzip unrar"				#ziptools
	"viewnior"						#pic viewer / gpicview
	"beaver"						#gui text editor
	"evince"						#pdf reader
	"firefox"						#browsr - chromium for plebs
	"python2 python3"				#2.7.x #python for 3.x.x
	"scrot" 						#screenshot - shutter
);

services_user=();

#AUR packages
install_pkgs_aur=(); #acpi_call, ttf-fonts-win7 thermald pulseaudio-ctl #flashplugin -> shumway(aur)

#firewall - iptables open ports - disable to stop setting up firewall
ipt_openports_all=("loopback" "established" "ssh" "avahi" "transmission-daemon"
					"mpd" "http" "https" "dns" "ping/pingblock/pinglimit" "synblock" "ftpbrute");
#default
ipt_openports=("loopback" "established" "ssh" "ping");

#user config git - separate script to push the files (linkthedots.sh)
user_config_git="";

#=======================================================================
#Presets
#=======================================================================
function select_preset() { #register the preset here, then define its parameters in the case block
	presetlist=("desktop"
				"laptop"
				"vm"
				"wizard" #DO NOT REMOVE as this one actually runs the wizard
				#add more here
	)
	needed_functions="check preinst postinst systemconf userconf";
	#if any of the functions that need preser is run
	if [ `echo "$needed_functions" | grep -wo "$1"` ];
	then
		echo "Select preset to initialize:"
		select preset in "${presetlist[@]}";
		do
			if [ "$preset" != "" ];
			then
				#echo $preset;
				case $preset in
#======================================================================
					"desktop") #example cofiguration 01
						echo "Using preset: $preset";
						hostname="desktop";

						#network
						net_connection_type="wired";
						ip_type="dhcp";

						#mounts
						#REQUIRED
						mount_root="/dev/sda1";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;
						#optional
						mount_swap="/dev/sda2";
						#optional
						mount_home="/dev/sda3";mountpoint_home="/mnt/home";fstype_root="ext4";format_home=true;

						#grub
						grub_device="/dev/sda";

						#pacman packages
						install_pkgs_user+=(
							"$opt_pkgs_gfx_intel"	#graphics driver
						#	"xscreensaver"			#screensaver
						#	"xcompmgr"				#compositor
							"mpd mpc ncmpcpp"		#audio player
							"mpv"					#video whaawmp / vlc
							"transmission-cli"		#set runtime user in systemd units..config from git #torrent
							"$opt_pkgs_vbox"		#virtual box
						#	"geany"					#IDE
						#	"geeqie"				#for viewing raw files
						#	"beets"					#needs python, mutagen #music organizer
						#	"sox"					#audio converter-> flac
						#	"mutagen hachoir-core hachoir-metadata" #meta viewer (python)
						#	"python2-pillow"		#image editing library
						);

						#services
						services_user+=("dkms")

						#AUR packages
						install_pkgs_aur+=("sublime-text")

						#user config src - git repo
						user_config_git="";

						ipt_openports=("loopback" "established" "ssh" "ping" "synblock" "ftpbrute");

						break;
					;;
#======================================================================
					"laptop") #example config 02
						echo "Using preset: $preset";
						hostname="laptop";

						#network
						net_interface="enp6s25";
						net_connection_type="wifi";
						ip_type="dhcp";

						#mounts
						#REQUIRED
						mount_root="/dev/sdb1";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;
						#optional
						mount_swap="/dev/sdb2";
						#optional
						mount_home="/dev/sdb3";mountpoint_home="/mnt/home";fstype_root="ext4";format_home=false;

						#grub
						grub_device="/dev/sdb";

						#pacman packages
						install_pkgs_user+=(
							"acpi" 					#acpid client #battery monitor
						#	"pm-utils powertop" 	#checkout tlp
							"$opt_pkgs_gfx_intel"	#graphics drivers
							"$opt_pkgs_gfx_nvidia"	#add user to group bumblebee-> gpasswd -a "$user_name" bumblebee;
						#	"xscreensaver"			#screensaver
						#	"xcompmgr"				#compositor
							"xf86-input-synaptics"	#touchpad
						#	"geany"					#IDE
							"cmus"					#music
							"mpv"					#video whaawmp / vlc
							"transmission-gtk"		#torrent
							"$opt_pkgs_libreoffice"	#office
						);

						#services
						services_user+=("bumblebeed")

						#AUR packages
						install_pkgs_aur+=("sublime-text")

						#user config src - git repo
						user_config_git="";

						ipt_openports=("loopback" "established" "ssh" "ping" "synblock" "ftpbrute");

					break;
					;;
#======================================================================
					"vm") #example config 03
						echo "Using preset: $preset";
						hostname="archvm";
						#mounts
						#REQUIRED
						mount_root="/dev/sdc1";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;

						#grub
						grub_device="/dev/sdc";

						#pacman packages
						#install_pkgs_user+=(
						#graphics driver
						#	"$opt_pkgs_gfx_intel"
						#);

						#services
						services_user+=()

						#AUR packages
						install_pkgs_aur+=()

						#user config src - git repo
						user_config_git="";

						break;
					;;
#======================================================================
					#DO NOT REMOVE THIS ONE ACTUALLY STARTS THE WIZARD
					"wizard")
						echo "Starting wizard..."
						run_config_wiz=true; #runs configuration wizard. auto run if no preset defind/found.
						break;
					;;
#======================================================================
					#define more presets here
					#"presetname")
					#	parameters;
					#	break;
					#;;
#======================================================================
				esac;
			fi;
			#else
			echo "Invalid preset. Please try again...";
		done;
	fi;
}
#======================================================================
#functions
#=======================================================================
function print_block() { #separates different procedures by printing blocks of text, keeps track of time elapsed
	echo "========================================================================";
	echo "$@";
	echo "[`date`]";
	echo "========================================================================";
	sleep 0;
}

function get_script() { #provided $scriptsrc is set, checks if newer version is available > updates.
	if [ "$scriptsrc" != "" ];
	then
		if [ $dry_run == false ];
		then
			wget $scriptsrc -O $0.new || echo "Update failed.";
			#check if different then replace
			if [ "`diff $0 $0.new`" != "" ];
			then
				echo "Updating script to last stable version.";
				mv $0.new $0;
			else
				echo "Script is the last stable version.";
				rm $0.new;
			fi;
		fi;
	else
		echo "Scriptsrc is invalid."
	fi;
}

function get_rootdir() { #the dir the script is in, every files is stored relevant to this dir, else in /tmp/
	filepath=`readlink -f $0`;
	rootdir="${filepath%/*}";
	echo $rootdir;
}

function net_connected() { #check if connected to internet
	ping -q -w 1 -c 1 8.8.8.8 > /dev/null && echo 1 || echo 0; #google dns
}

function ask_for_value() { #ask for value if value invalid #$1=prompt. # ignores blank lines and  always returns capital
	value='';
	while true;
	do
		read -p "$1" value;
		if [ "$value" != "" ];
		then
			echo ${value^^};
			return 0;
		fi;
	done;
}

function needsudo() { #check if user has sudo privilege, else prompt and exit
	if [ $dry_run == false ] && [ $EUID != 0 ]; then print_block "Cannot run without being root. Exiting."; exit 1;
	else return 0;
	fi;
}

function get_iso() { #locate $arch_iso if set, else download from $arch_mirror and set $arch_iso
	if [ `net_connected` != 1 ];
	then echo "Internet disconnected."; exit 1;
	fi;
	#download iso, return path/to/iso
	#download and find latest arch-*-dual.iso
	echo "Getting archiso from: "$arch_mirror;
	if [ $dry_run == false ];
	then
		/usr/bin/wget -r -np "$arch_mirror" -A "$arch_isonamereg" -P `get_rootdir`;
		#locate iso
		isopath=`find $rootdir -name "$arch_isonamereg" -type f`;
		echo "ISOpath: $isopath";
		arch_iso="$isopath";
	else
		echo "Set dry_run to false to start download.";
	fi;
}

function get_sig() { #locate $arch_sig if set, else download from $arch_mirror and set $arch_sig
	if [ `net_connected` != 1 ];
	then echo "Internet disconnected."; exit 1;
	fi;
	#download signature, return path/to/signature
	echo "Getting iso.signature from: "$arch_mirror;
	if [ $dry_run == false ];
	then
		/usr/bin/wget -r -np "$arch_mirror" -A "$arch_isonamereg.sig" -P `get_rootdir`;
		#locate signature
		sigpath=`find $rootdir -name "$arch_isonamereg.sig" -type f`;
		echo "SIGpath: $sigpath";
		arch_sig="$sigpath";
	else
		echo "Set dry_run to false to start download.";
	fi;
}

function verify_iso() { #$1=/path/to/signature.sig #must be in the same dir as the iso, does not work for OSs other than Arch
	sigpath="$1";
	#make sure sig exists and archiso and sig in same folder
	if [ ! -e $sigpath ]; then echo "Cannot find signature."; return 1;fi;
	if [ ! "$arch_iso.sig" -eq $sigpath ]; then echo "Iso and signature must be in same folder."; return 1;fi;
	if [ `uname -r | grep "ARCH"` ];
	then
		echo "OS: ArchLinux; Checking signature: $sigpath";
		if [ $dry_run == false ];
		then
			veri=`pacman-key -v "$sigpath" 1>/dev/null 2>/dev/null && echo 1 || echo 0`; #op and error to /dev/null
			#echo $veri;
			if [ $veri == 1 ];
			then
				echo "ISO verified succesfully."; return 0;
			else
				echo "Cannot verify ISO."; return 1;
			fi;
		fi;
	else #other os
		echo "OS isn't ArchLinux; Checking signature of $isopath";
		echo "Cannot check signature without pubkey. Not implemented.";
		#if [ $dry_run == false ];
		#then gpg2 --verify "$sigpath"; fi;#fails without the pubkey TODO
	fi;
}

function check_efi() { #check if booted up with EFI mode, Does not work with EFI yet.
	echo "Checking if UEFI...(might give an error or two here, no need to panic.)";
	if [ $dry_run == false ];then mount -t efivarfs efivarfs /sys/firmware/efi/efivars; fi; # ignore if already mounted
	efivar -l;
	#if all listed correct then bootmode=uefi
	if [ $? == 0 ];
	then
		echo "UEFI mode detected. Doesn't work with UEFI yet."; return 0;
	else
		echo "Not UEFI. Continuing with installation..."; return 1;
	fi;
}

function rank_mirrors_by_speed() { #set mirrors using rankmirrors #needs sudo
	needsudo;

	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup;
	sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup; #uncomments every mirror
	rankmirrors /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist; #tests the mirrors and arranges by fastest
	echo "Finished generating mirrors.";
}

function mount_device() { #mount devices  #args: $device $mountpoint $fstype $format_if_true #only used internally
	if [ "$1" == "" ]; then echo "Invalid block device"; return 1; fi;
	#if mountpoint does not exits -  #TODO: custom mountpoints like /data/home/
	if [ ! -d  "$2" ];
	then
		if [ $dry_run == false ]; then mkdir -p "$2" || return $?; fi;
	fi;
	#elif valid block device
	if [ -b "$1" ];
	then
		#format if set so
		if [ $4 == true ];
		then
			echo "Formatting $1 as $3";
			if [ $dry_run == false ]; then mkfs -t "$3" "$1" || return $?; fi;
		else echo "Continuing without formatting $1";
		fi;
		#mount root to /mnt
		echo "Mounting (type:$3)$1 to $2";
		if [ $dry_run == false ]; then mount -t "$3" "$1" "$2" && return 0 || return $?; fi;
	else
		echo "Mount point: $1  is not valid.";
		return 2;
	fi;
}

function run_mounts() { #mount drives to their mount points #DOES NOT work with custom mountpoints
	needsudo;

	#root
	mount_device "$mount_root" "$mountpoint_root" "$fstype_root" "$format_root";
	if [ $? -gt 0 ];
	then
		echo "Cannot continue without root device mounted. Exiting...";
		if [ $dry_run == false ]; then exit 1; fi;
	fi;

	#boot
	mount_device "$mount_boot" "$mountpoint_boot" "$fstype_boot" "$format_boot";
	if [ $? -gt 0 ];
	then
		echo "Block device \"$mount_boot\" invalid or not specified.";
		#if [ `ask_for_value "If /boot/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_boot.Continue without a separate drive?(Y/n)"` != "Y" ];
		#then
		#	echo "Exiting...";
		#	exit 1;
		#fi;
	fi;

	#home
	mount_device "$mount_home" "$mountpoint_home" "$fstype_home" "$format_home";
	if [ $? -gt 0 ];
	then
		echo "Block device \"$mount_home\" invalid or not specified.";
		#if [ `ask_for_value "If /home/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_home.Continue without a separate drive?(Y/n)"` != "Y" ];
		#then
		#	echo "Exiting...";
		#	exit 1;
		#fi;
	fi;

	#etc
	mount_device "$mount_etc" "$mountpoint_etc" "$fstype_etc" "$format_etc";
	if [ $? -gt 0 ];
	then
		echo "Block device \"$mount_etc\" invalid or not specified.";
		#if [ `ask_for_value "If /etc/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_etc.Continue without a separate drive?(Y/n)"` != "Y" ];
		#then
		#	echo "Exiting...";
		#	exit 1;
		#fi;
	fi;

	#var
	mount_device "$mount_var" "$mountpoint_var" "$fstype_var" "$format_var";
	if [ $? -gt 0 ];
	then
		echo "Block device \"$mount_var\" invalid or not specified.";
		#if [ `ask_for_value "If /var/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_var.Continue without a separate drive?(Y/n)"` != "Y" ];
		#then
		#	echo "Exiting...";
		#	exit 1;
		#fi;
	fi;

	#usr
	mount_device "$mount_usr" "$mountpoint_usr" "$fstype_usr" "$format_usr";
	if [ $? -gt 0 ];
	then
		echo "Block device \"$mount_usr\" invalid or not specified.";
		#if [ `ask_for_value "If /usr/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_usr.Continue without a separate drive?(Y/n)"` != "Y" ];
		#then
		#	echo "Exiting...";
		#	exit 1;
		#fi;
	fi;

	##tmp
	#if [ $dry_run == false ] && [ -e "$mount_tmp" ];
	#then
	#	mount "$mount_tmp" "/mnt/tmp";
	#	echo "Mounted $mount_tmp to /mnt/tmp";
	#else echo "Mount point tmp: $mount_tmp not set or not found or dry_run=true."; fi;

	#swap
	if [ $dry_run == false ] && [ -e "$mount_swap" ];
	then
		mkswap "$mount_swap";
		swapon "$mount_swap";
		echo "Mounted $mount_swap as swap";
	else echo "Mount point swap: $mount_swap not set or not found or dry_run=true."; fi;

	#check if drives are correctly mounted else exit
	echo "Mounts:";
	mount|grep "^/dev/";
	#if [ "`ask_for_value "Continue with this configuration?(Y/n)"`" == "N" ];
	#then
	#	echo "Exiting. Please manually mount atleast the root drive to /mnt and re-run script."
	#	exit 1;
	#fi;
	sleep 5;
}

function networker() { #setup network with wicd-curses, or wifi-menu, or manually. get values from config
	needsudo;

	echo "Checking internet connection...";
	if [ `net_connected` == 1 ]; then echo "Internet connected"; return 0;
	#run wicd-curses if found
	elif [ `which "wicd-curses" > /dev/null && echo 1 || echo 0` == 1 ];
	then
		echo "Starting wicd-curses.";
		if [ $dry_run == false ];
		then
			#start_service wicd; #enable and start else restart
			#disable dhcpcd
			systemctl stop dhcpcd.service;
			#systemctl disable dhcpcd.service;

			systemctl enable wicd.service;
			systemctl start wicd.service;
			wicd-curses;
		fi;
	#setup mnually - only for preinstallation
	else
		echo "Running manual setup...";
		echo "Connection status:";
		ip a;
		echo;

		#select interface
		options="`ls /sys/class/net/`";
		if [ -z "$net_interface" ] || [ "`echo "$options" | grep -wo "$net_interface"`" == "" ];
		then
			echo "Available interfaces:";
			select opt in $options;
			do
				if [ "$opt" != "" ]; then net_interface="$opt"; break; fi;
				#else
				echo "Invalid option."
			done;
		else
			echo "Using interface: $net_interface";
		fi;

		#select connection type
		options="wired wifi";
		if [ -z "$net_connection_type" ] || [ "`echo "$options" | grep -wo "$net_connection_type"`" == "" ];
		then
			echo "Connection type:";
			select opt in $options;
			do
				if [ "$opt" != "" ]; then net_connection_type="$opt"; break; fi;
				#else
				echo "Invalid option."
			done;
		else
			echo "Using connection type: $net_connection_type";
		fi;

		#select ip type
		options=("static dhcp");
		if [ -z "$ip_type" ] || [ "`echo "$options" | grep -wo "$ip_type"`" == "" ];
		then
			echo "IP type: "
			select opt in $options;
			do
				if [ "$opt" != "" ]; then ip_type="$opt"; break; fi;
				#else
				echo "Invalid option";
			done;
		else
			echo "Using IP type: $ip_type";
		fi;

		if [ "$ip_type" == "static" ];
		then
			echo "Enter Static Address information:";
			if [ -z "$net_ip" ]; then			net_ip="`ask_for_value "IP Address: "`"; fi;
			if [ -z "$net_mask" ];
			then
				read -p "NetMask(CIDR)(default: 24): " net_mask_temp;
				[[ $net_mask_temp ]] && net_mask=$net_mask_temp || net_mask="24";
			fi;
			if [ -z "$net_broadcast" ]; then 	net_broadcast="`ask_for_value "Broadcast Address: "`"; fi;
			if [ -z "$net_gateway" ]; then		net_gateway="`ask_for_value "Gateway: "`"; fi;
			if [ -z "$net_nameserver" ];
			then
				read -p "DNS(default: 8.8.8.8): " net_nameserver_temp;
				[[ $net_nameserver_temp ]] && net_nameserver=$net_nameserver_temp || net_nameserver="8.8.8.8";
			fi;
		fi;

		#echo $net_interface $net_connection_type;
		if [ "$net_connection_type" == "wired" ];
		then
			echo "Setting up wired connection...";
			#dhcp
			if [ "$ip_type" == "dhcp" ];
			then
				echo "Tuning on interface: $net_interface and restarting DHCP...";
				if [ $dry_run == false ];
				then
					ip link set dev "$net_interface" up;
					systemctl restart dhcpcd.service;
				fi;
			#static
			elif [ "$ip_type" == "static" ];
			then
				echo "Setting up static address on interface: $net_interface";
				echo "IP: $net_ip/$net_mask";
				echo "BCAST: $net_broadcast";
				echo "GATEWAY: $net_gateway";
				echo "DNS: $net_nameserver";
				if [ $dry_run == false ];
				then
					#stop dhcp
					systemctl stop dhcpcd.service;
					#setup static ip
					ip link set dev "$net_interface" up;
					sudo ip addr add "$net_ip/$net_mask" broadcast "$net_broadcast" dev "$net_interface";
					sudo ip route add default via "$net_gateway";
					echo "nameserver $net_nameserver" > /etc/resolv.conf;
				fi;
			fi;
		#wifi
		elif [ "$net_connection_type" == "wifi" ];
		then
			if [ $dry_run == false ];
			then
				wifi-menu "$net_interface";
			fi;
		fi;
	fi;
}

function generate_locales() { #generates locales for each item in array gen_locales[*] #needs su
	needsudo;

	#generate locales
	for index in ${!gen_locales[*]};
	do
		l="${gen_locales[$index]}";
		echo "$l";
		sed -i "s/#$l/$l/" /etc/locale.gen; #uncomments every locale in ${gen_locales}
	done;
	#generate locales
	locale-gen;
	#set system wide locales
	echo "LANG=${gen_locales[0]}" > /etc/locale.conf;		#locaLectl set-locale LANG="${gen_locales[0]}";
	echo "LC_COLLATE=C" >> /etc/locale.conf;				#localectl set-locale LC_COLLATE="C";
	echo "LC_TIME=${gen_locales[0]}" >> /etc/locale.conf;	#localectl set-locale LC_TIME="${gen_locales[0]}";
	#locale > /etc/locale.conf;
}

function set_time() { #setup localtime and hwclock #needs su
	needsudo;

	if [ $dry_run == false ];
	then
		if [ -e "/etc/localtime" ]; then rm /etc/localtime; fi;
		ln -sf /usr/share/zoneinfo/"$time_zone/$time_subzone" /etc/localtime;
		#set hardware clock to utc
		hwclock --systohc --utc;
	else
		echo "Time: `date`";
	fi;
}

function setup_iptables() { #firewall rules here #needs su
	needsudo;

	print_block "Setting up iptables_v4.";

	#flush all rules first
	echo "Flushing all previous rules.";
	if [ $dry_run == false ];
	then
		iptables -F;
		iptables -X;
	fi;

	#default
	echo "Default: In: Drop / Fwd: Drop / Out: Accept.";
	if [ $dry_run == false ];
	then
		iptables -P INPUT DROP;										# Set default chain policies to DROP
		iptables -P FORWARD DROP;										# Set default chain policies to DROP
		iptables -P OUTPUT ACCEPT;
	fi;

	# Drop all traffic of state "INVALID"
	echo "Dropping all invalid.";
	if [ $dry_run == false ];
	then
		#iptables -A INPUT -m conntrack --ctstate INVALID -j DROP;
		#or
		iptables -A INPUT   -m state --state INVALID -j DROP; # Drop invalid packets
		iptables -A FORWARD -m state --state INVALID -j DROP; # Drop invalid packets
		iptables -A OUTPUT  -m state --state INVALID -j DROP; # Drop invalid packets
	fi;

	#loopback - Accept all traffic from loopback interface
	if [ "`echo ${ipt_openports[*]} | grep -iosw "loopback"`" ];
	then
		echo "Allow all from loopback."
		if [ $dry_run == false ];
		then
			iptables -A INPUT -i lo -j ACCEPT;
		fi;
	fi;

	# Allow all traffic belonging to established connections, or new valid traffic related to these connections (such as ICMP error)
	#iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT;
	if [ "`echo ${ipt_openports[*]} | grep -iosw "established"`" ];
	then
		echo "Allow all from established/related."
		if [ $dry_run == false ];
		then
			iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT;
			iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT;
		fi;
	fi;

	#ports
	#ssh
	if [ "`echo ${ipt_openports[*]} | grep -iosw "ssh"`" ];
	then
		#echo "Allow ssh on port 22";
		#iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT;
		#or
		echo "Limiting SSH."
		if [ $dry_run == false ];
		then
			iptables -N IN_SSH;
			iptables -A INPUT -p tcp --dport ssh -m conntrack --ctstate NEW -j IN_SSH;
			iptables -A IN_SSH -m recent --name sshbf --rttl --update --hitcount 3 --seconds 10 -j DROP; #rcheck replaced with update
			iptables -A IN_SSH -m recent --name sshbf --rttl --update --hitcount 4 --seconds 1800 -j DROP ; #rcheck replaced with update
			iptables -A IN_SSH -m recent --name sshbf --set -j ACCEPT;
		fi;
	fi;

	#avahi
	if [ "`echo ${ipt_openports[*]} | grep -iosw "avahi"`" ];
	then
		echo "Allowing avahi: 5353/UDP";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p udp --dport 5353 -j ACCEPT; #removed -m udp
		fi;
	fi;

	#torrent - transmission-daemon
	if [ "`echo ${ipt_openports[*]} | grep -iosw "transmission-daemon"`" ];
	then
		echo "Allowing transmission-daemon webUI: 9091/TCP";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --dport 9091 -m state --state NEW,ESTABLISHED -j ACCEPT;		#PORT 9091   http  - Allow connections from anywhere
		fi;
	fi;

	#mpd
	if [ "`echo ${ipt_openports[*]} | grep -iosw "mpd"`" ];
	then
		echo "Allowing mpd: 6600,8000 from localhost.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --dport 6600 -s 192.168.1.0/24 -m state --state NEW,ESTABLISHED -j ACCEPT;		#PORT 6600   mpd - only local
			iptables -A INPUT -p tcp -m tcp --dport 8000 -s 192.168.1.0/24 -m state --state NEW,ESTABLISHED -j ACCEPT;		#PORT 6600   mpd - only local
		fi;
	fi;

	#http(s)
	if [ "`echo ${ipt_openports[*]} | grep -iosw "http"`" ];
	then
		echo "Allowing http: 80/tcp.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT;			# PORT 80   http  - Allow connections from anywhere
		fi;
	fi;
	if [ "`echo ${ipt_openports[*]} | grep -iosw "https"`" ];
	then
		echo "Allowing https: 443/tcp.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT;			# PORT 443  SSL    - Allow connections from anywhere
		fi;
	fi;

	#dns
	if [ "`echo ${ipt_openports[*]} | grep -iosw "dns"`" ];
	then
		echo "Allowing dns: 53/tcp-udp.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --dport 53 -j ACCEPT;
			iptables -A INPUT -p udp --dport 53 -j ACCEPT; #removed -m udp
		fi;
	fi;

	# Drop echo requests so people can not ping us
	if [ "`echo ${ipt_openports[*]} | grep -iosw "ping"`" ];
	then
		echo "Allowing ping to host.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p icmp --icmp-type 8 -j ACCEPT;
		fi;
	elif [ "`echo ${ipt_openports[*]} | grep -iosw "pingblock"`" ];
	then
		echo "Dropping ICMP ping requests.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p icmp --icmp-type 8 -m conntrack --ctstate NEW -j DROP;
		fi;
	elif [ "`echo ${ipt_openports[*]} | grep -iosw "pinglimit"`" ];
	then
		echo "Limiting ICMP ping requests.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p icmp --icmp-type echo-request -m recent --name ping_limiter --set;
			iptables -A INPUT -p icmp --icmp-type echo-request -m recent --name ping_limiter --update --hitcount 6 --seconds 4 -j DROP;
			iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT;
		fi;
	fi;

	# SYNFLOOD CHAIN
	if [ "`echo ${ipt_openports[*]} | grep -iosw "synblock"`" ];
	then
		echo "Dropping SYN,RST / SYN,FIN packets.";
		if [ $dry_run == false ];
		then
			iptables -A INPUT -p tcp -m tcp --tcp-flags SYN,FIN SYN,FIN -j DROP; # Drop TCP - SYN,FIN packets
			iptables -A INPUT -p tcp -m tcp --tcp-flags SYN,RST SYN,RST -j DROP; # Drop TCP - SYN,RST packets
			iptables -A INPUT -m state --state NEW -p tcp -m tcp --syn -m recent --name SYNFLOOD --set;
			iptables -A INPUT -m state --state NEW -p tcp -m tcp --syn -m recent --name SYNFLOOD --update --seconds 1 --hitcount 20 -j DROP;
		fi;
	fi;

	# FTP_BRUTE CHAIN
	if [ "`echo ${ipt_openports[*]} | grep -iosw "ftpbrute"`" ];
	then
		echo "Dropping FTP bruteforce packets."
		if [$dry_run == false ];
		then
			iptables -A INPUT -p tcp -m multiport --dports 20,21 -m state --state NEW -m recent --set --name FTP_BRUTE;
			iptables -A INPUT -p tcp -m multiport --dports 20,21 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --rttl --name FTP_BRUTE -j DROP;
		fi;
	fi;

	# Logging CHAIN
	echo "Enabling logging chain for dropped packets.";
	if [ $dry_run == false ];
	then
		iptables -N LOGGING	;											# Create `LOGGING` chain for logging denied packets
		iptables -A INPUT -j LOGGING;											# Create `LOGGING` chain for logging denied packets
		iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables Packet Dropped: " --log-level 6;	# Log denied packets to /var/log/messages
		iptables -A LOGGING -j DROP;
	fi;

	# Be RFC compliant and imitate default linux behavior
	echo "RFC compliance and imitate default linux behavior.";
	if [ $dry_run == false ];
	then
		iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable;
		iptables -A INPUT -p tcp -j REJECT --reject-with tcp-rst;
	fi;

	# Reject all other protocols using ICMP
	echo "Reject all other protocols using ICMP";
	if [ $dry_run == false ];
	then
		iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable;
	fi;

	#drop everything else on INPUT and FORWARD
	echo "Drop everything else.";
	if [ $dry_run == false ];
	then
		iptables -A INPUT -j DROP;
		iptables -A FORWARD -j DROP;
	fi;

	#write rules in file
	echo "Writing config to /etc/iptables/iptables.rules";
	if [ $dry_run == false ];
	then
		iptables-save > /etc/iptables/iptables.rules;
	fi;

	#enable service
	start_service iptables.service;

	#block all v6
	print_block "Setting up iptables_v6.";
	#flush all rules first
	echo "Flushing all previous rules.";
	if [ $dry_run == false ];
	then
		ip6tables -F;
		ip6tables -X;
	fi;
	#default
	echo "Default: In: Drop / Fwd: Drop / Out: Drop.";
	if [ $dry_run == false ];
	then
		ip6tables -P INPUT DROP;										# Set default chain policies to DROP
		ip6tables -P FORWARD DROP;										# Set default chain policies to DROP
		ip6tables -P OUTPUT DROP;										# Set default chain policies to DROP
	fi;
	#write rules in file
	echo "Writing config to /etc/iptables/ip6tables.rules";
	if [ $dry_run == false ];
	then
		ip6tables-save > /etc/iptables/ip6tables.rules;
	fi;

	#enable service
	start_service ip6tables.service;
}

function install_packages() { #install packages in "$1" with pacman e.g> install_packages "${install_pkgs_system[*]}"; #needs su
	needsudo;

	#check internet
	packagelist="$@";
	echo "Checking Internet connection...";
	if [ `net_connected` == 1 ];
	then
		echo "Internet connected.";
		#system packages install / services start
		print_block "Running packages install..."
		print_block "Packages: $packagelist";
		if [ $dry_run == false ];
		then
			pacman -Syu $packagelist; fi;
		return 0;
	else
		echo "Internet not connected. Skipping package install...";
		return 1;
		#if [ $dry_run == false ]; then networker; fi;
	fi;
}

function start_service() { #enables and starts service, or reloads if running #args: $@=PATTERNLIST
	needsudo;

	for serv in $@;
	do
		#check if enabled, else enable
		if [ `systemctl is-enabled "$serv" --quiet && echo 0 || echo 1` == 0 ];
		then
			echo "$serv: Already enabled.";
		else
			echo "Enabling $serv";
			if [ $dry_run == false ];
			then
				systemctl enable "$serv";
			fi;
		fi;
		if [ `systemctl is-active "$serv" --quiet && echo 0 || echo 1` == 0 ];
		then
			#echo "Already running $serv";
			echo "Restarting $serv";
			if [ $dry_run == false ]; then systemctl restart "$serv";fi;
		else
			echo "Starting $serv";
			if [ $dry_run == false ]; then systemctl start "$serv"; fi;
		fi;
	done;
}

function generate_sshkeys() { #generates moderately strong ssh keypairs
	if [ -f "$HOME/.ssh/id_rsa" ];
	then echo "Key exists."; return 1;
	else
		curdir=`pwd`;
		mkdir -p "$HOME/.ssh"; #if not exists
		cd "$HOME/.ssh";
		ssh-keygen -t rsa -b 4096 -C "$(whoami)@$(hostname)-$(date -I)"; #generate keys
		#ssh-keygen -f ~/.ssh/id_rsa -p #to change passphrase
		#ssh-copy-id username@address -i /path/to.keyfile -p port # to copy key to remote machine
		cd "$curdir";
	fi;
}

function config_wiz() { #$1 = type of info to show -> preinst, postinst, systemconf, userconf, showall for all
	clear;
	if [ "$1" == "preinst" ] || [ "$1" == "showall"  ];
	then
		print_block "Running Wizard >> preinst";
		read -p "Enter Hostname:" hostname;

		read -p "Keyboard layout(default: us):" kb_layout_temp;
		[[ $kb_layout_temp ]] && kb_layout=$kb_layout_temp; #use value as keymap if not none;

		#mounts
		#show block devices

		echo "Listing block devices:";
		if [ $dry_run == false ];
		then
			fdisk -l | grep -i '/dev/sd[a-z]';
		else
			sudo fdisk -l | grep -i '/dev/sd[a-z]';
		fi;
		#root
		read -p "Block device -> root($mountpoint_root):" mount_root;
		read -p "Filesystem(default: ext4):" fstype_root_temp;
		[[ $fstype_root_temp ]] && fstype_root=$fstype_root_temp || fstype_root="ext4";
		read -p "Format device?(t/F)" fds;
		[[ ${fds^^} == "T" ]] && format_root=true || format_root=false;

		echo "All other mounts are optional. If skipped, they will be created as directories in /, e,g /home /etc";
		echo "Press <enter> to skip.";

		#swap
		read -p "Block device -> swap:" mount_swap;

		#home
		read -p "Block device -> home($mountpoint_home):" mount_home;
		if [ "$mount_home" != "" ];
		then
			read -p "Filesystem(default: ext4):" fstype_home_temp;
			[[ $fstype_home_temp ]] && fstype_home=$fstype_home_temp || fstype_home="ext4";
			read -p "Format device?(t/F)" fds;
			[[ ${fds^^} == "T" ]] && format_home=true || format_home=false;
		fi;

		#boot
		read -p "Block device -> boot($mountpoint_boot):" mount_boot;
		if [ "$mount_boot" != "" ];
		then
			read -p "Filesystem(default: ext4):" fstype_boot_temp;
			[[ $fstype_boot_temp ]] && fstype_boot=$fstype_boot_temp || fstype_boot="ext4";
			read -p "Format device?(t/F)" fds;
			[[ ${fds^^} == "T" ]] && format_boot=true || format_boot=false;
		fi;

		#var
		read -p "Block device -> var($mountpoint_var):" mount_var;
		if [ "$mount_var" != "" ];
		then
			read -p "Filesystem(default: ext4):" fstype_var_temp;
			[[ $fstype_var_temp ]] && fstype_var=$fstype_var_temp || fstype_var="ext4";
			read -p "Format device?(t/F)" fds;
			[[ ${fds^^} == "T" ]] && format_var=true || format_var=false;
		fi;

		#etc
		read -p "Block device -> etc($mountpoint_etc):" mount_etc;
		if [ "$mount_etc" != "" ];
		then
			read -p "Filesystem(default: ext4):" fstype_etc_temp;
			[[ $fstype_etc_temp ]] && fstype_etc=$fstype_etc_temp || fstype_etc="ext4";
			read -p "Format device?(t/F)" fds;
			[[ ${fds^^} == "T" ]] && format_etc=true || format_etc=false;
		fi;

		#usr
		read -p "Block device -> usr($mountpoint_usr):" mount_usr;
		if [ "$mount_usr" != "" ];
		then
			read -p "Filesystem(default: ext4):" fstype_usr_temp;
			[[ $fstype_usr_temp ]] && fstype_usr=$fstype_usr_temp || fstype_usr="ext4";
			read -p "Format device?(T/f)" fds;
			[[ ${fds^^} == "T" ]] && format_usr=true || format_usr=false;
		fi;

		#strap packages
		echo "Default package groups: $strap_pkgs";
		read -p "Additional packages:" add_packs;
		strap_pkgs+=" $add_packs";
	fi;

	if [ "$1" == "postinst" ] || [ "$1" == "showall"  ];
	then
		print_block "Running wizard >> postinst"
		echo "Default locales: ${gen_locales[*]}";
		read -p "Additional locales:" add_locales;
		gen_locales+=("$add_locales");

		echo "Timezone options:";
		ls -C  /usr/share/zoneinfo/ | sed s_\/_''_g;
		read -p "Timezone(default: Asia):" time_zone;
		[[ $time_zone_temp ]] && time_zone=$time_zone_temp || time_zone="Asia";
		echo "Time-subzone options:";
		ls -C /usr/share/zoneinfo/$time_zone | sed s_\/_''_g;
		read -p "Time-subzone(default: Kolkata):" time_subzone_temp;
		[[ $time_subzone_temp ]] && time_subzone=$time_subzone_temp || time_subzone="Kolkata";

		#grub
		#show block devices
		echo "Listing block devices:";
		if [ $dry_run == false ];
		then
			fdisk -l | grep -io '/dev/sd[a-z]' | uniq;
		else
			sudo fdisk -l | grep -io '/dev/sd[a-z]' | uniq;
		fi;
		read -p "Bootloader device(default: /dev/sda):" grub_device_temp;
		[[ -e $grub_device_temp ]] && grub_device=$grub_device_temp || grub_device="/dev/sda";

		#user
		read -p "Enter Username(default: arch):" user_name;
		[[ -z $user_name ]] && user_name="arch";
		echo "Shell options: `chsh -l`";
		read -p "Shell(default: /bin/bash):" user_shell_temp;
		[[ $user_shell_temp ]] && user_shell=$user_shell_temp || user_shell="/bin/bash";
	fi;

	if [ "$1" == "systemconf" ] || [ "$1" == "showall"  ];
	then
		print_block "Running wizard >> systemconf";
		#install_pkgs_system
		echo "System Packages";
		echo "${install_pkgs_system[*]}";
		read -p "Additional packages:" add_ipacks;
		install_pkgs_system+=("$add_ipacks");

		echo "System services:";
		echo "${services_system[*]}";
		read -p "Additional service:" add_services;
		services_system+=("$add_services");

		#install_pkgs_user
		echo "User Packages";
		echo "${install_pkgs_user[*]}";
		read -p "Additional packages:" add_upacks;
		install_pkgs_user+=("$add_upacks");

		echo "User services:";
		echo "${services_user[*]}";
		read -p "Additional services:" add_uservices;
		services_user+=("$add_uservices");

		echo "Firewall available ports:";
		echo "${ipt_openports_all[*]}";
		echo "Firewall default ports to open:";
		echo "${ipt_openports[*]}";
		read -p "Additional ports:" add_iports;
		ipt_openports+=("$add_iports");
	fi;

	if [ "$1" == "userconf" ] || [ "$1" == "showall"  ];
	then
		print_block "Running wizard >> userconf";
		#install_pkgs_aur
		echo "AUR Packages";
		echo "${install_pkgs_aur[*]}";
		read -p "Additional packages:" add_aur;
		install_pkgs_aur+=("$add_aur");

		#user config git #must have own script to push files to their places e.g linkthedots.sh
		if [ "$user_config_git" == "" ];
		then
			read -p "Enter dotfiles source(git):" user_config_git;
		else
			echo "User dotfiles source: $user_config_git";
		fi;
	fi;
}

function check_config() { #$1 = type of info to show -> preinst, postinst, systemconf, userconf, showall for all
	print_block "Running configuration selfcheck for <$1>...";
	#display configurations settings as needed
    echo "Dry_run=$dry_run";
    echo "Internet status...";
    [ `net_connected` ] && echo "...connected." || echo "...disconnected.";

    echo "Checking script source...";
	if [ $scriptsrc != "" ];
	then
		wget -q --spider $scriptsrc && echo "...valid." || echo "...invalid.";
	else
		echo "No script source.";
	fi;

    #preboot
    #print_block "Preboot Settings.";
    #echo "Checking iso download mirror validity..."
    #wget -q --spider $arch_mirror && echo "...valid." || echo "...invalid.";

    #preinst
	if [ "$1" == "preinst" ] || [ "$1" == "showall" ];
	then
		print_block "Pre-Installation Configurartion.";
		echo "Hostname:         $hostname";
		echo "Keyboard layout:  ${kb_layout^^}";
		echo "Net connection:   $net_connection_type";
		echo "IP type:          $ip_type";
		echo "Net interface:    $net_interface";
		echo;
		check_efi;
		echo;
		echo "Mounts : Format : Type :  Mount at :    Device";
		if [ -b "$mount_root" ];
		then
			echo "/      : $format_root     $fstype_root    $mountpoint_root          $mount_root";
		else
			echo "Check configuration, block device for / does not exist.";
		fi;
		if [ -b "$mount_home" ];
		then
			echo "/home  : $format_home     $fstype_home    $mountpoint_home     $mount_home";
		else
			echo "Check configuration, block device for /home does not exist.";
		fi;
		if [ -b "$mount_boot" ];
		then
			echo "/boot  : $format_boot    $fstype_boot     $mountpoint_boot     $mount_boot";
		else
			echo "Check configuration, block device for /home does not exist.";
		fi;
		if [ -b "$mount_var" ];
		then
			echo "/var   : $format_var     $fstype_var    $mountpoint_var      $mount_var";
		else
			echo "Check configuration, block device for /var does not exist.";
		fi;
		if [ -b "$mount_etc" ];
		then
			echo "/etc   : $format_etc     $fstype_etc    $mountpoint_etc      $mount_etc";
		else
			echo "Check configuration, block device for /etc does not exist.";
		fi;
		if [ -b "$mount_usr" ];
		then
			echo "/usr   : $format_usr     $fstype_usr    $mountpoint_usr      $mount_usr";
		else
			echo "Check configuration, block device for /usr does not exist.";
		fi;
		if [ -b "$mount_swap" ];
		then
			echo "swap   : N/A      N/A     N/A           $mount_swap";
		else
			echo "Check configuration, block device for /swap does not exist.";
		fi;
		echo;
		echo;
		echo "Initial package(s)-group(s): $strap_pkgs";
	fi;

    #postinst
	if [ "$1" == "postinst" ] || [ "$1" == "showall" ];
	then
		 print_block "Post-Installation Configurations.";
		echo "Locales ${gen_locales[*]}";
		echo "Timezone: $time_zone/$time_subzone";
		echo;
		echo "GRUB2 device: $grub_device";
		echo "";
		echo "User group: $user_grtype";
		echo "Username: $user_name";
		echo "Shell: $user_shell";
		echo "Add. groups: $user_gradd";
	fi;

    #system config
	if [ "$1" == "systemconf" ] || [ "$1" == "showall" ];
	then
		 print_block "System Configurations.";
		echo "Initial packages to be installed when configuring system:";
		echo ${install_pkgs_system[*]};
		echo;
		echo "Services to be enbled:";
		echo ${services_system[*]};
		echo;
		echo "Firewall open ports: ${ipt_openports[*]}";
		echo;
		echo "User specific packages:";
		echo ${install_pkgs_user[*]};
		echo;
		echo "User specific services:";
		echo ${services_user[*]};
	fi;

	if [ "$1" == "userconf" ] || [ "$1" == "showall" ];
	then
		print_block "Configuring User System.";
		echo "AUR packages:";
		echo ${install_pkgs_aur[*]};
		echo;
		echo "User configurations source(GIT): $user_config_git";
	fi;
	echo;
	echo "Finished checking configuration. Press Q to clear screen.";
	echo "If something needs to be changed, please amend in script before running preinstall(), otherwise unfortunate incidents may occur while installation.";
	echo "If all configuration is as needed, clear screen by pressing q and resume installation by agreeing to continue with pressing y."
	echo "";
}

function show_usage() {
	echo "Description:";
	echo "Semi-interactive Installer script for ArchLinux made by dawwg.";
	echo;
	echo "USB writing function in progress.";
	echo "Does not work with UEFI(yet).";
	echo "Remember to partition the disks manually before running installer."
	echo "Check out the presets first before choosing any to know what's happens underneath.";
	echo "Otherwise just choose wizard and enter the parameters manually at each step.";
	echo;
	echo "Functions:";
	echo "========================================================================";
	echo "(bash) $0 netcheck	-> check internet connection";
	echo "(bash) $0 getscript	-> get latest version of script";
	echo "(bash) $0 getscript	-> download latest version of script.";
	echo "(bash) $0 getiso	-> download latest dual iso";
	echo "(bash) $0 getsig	-> download signature of latest release";
	echo "(bash) $0 verify ./.sig-> verify iso signature.";
	echo "(bash) $0 networker	-> setup network.";
	echo "(bash) $0 rankmirrors	-> rank repo mirrors by speed.";
	echo "(bash) $0 mount	-> mount devices as set in config.";
	echo "(bash) $0 genlocale	-> generate locales defined in gen_locales.";
	echo "(bash) $0 settime	-> set timzone and hwclock as in config.";
	echo "(bash) $0 genssh	-> setup private/public keys.";
	echo "(bash) $0 firewall	-> setup iptables.";
	echo "(bash) $0 pacinst	-> install packaged listed after.";
	echo "(bash) $0 startservice	-> start or restart units listed after.";
	echo "(bash) $0 check	-> check and display own configuration.";
	echo;
	echo "Usage:";
	echo "========================================================================";
	echo "(bash) $0 make_usb	-> download and/or write usb.";
	echo "(bash) $0 preinst	-> run installer upto chroot.";
	echo "(bash) $0 postinst	-> run installer after chroot.";
	echo "(bash) $0 systemconf	-> user system configuration.";
	echo "(bash) $0 userconf	-> user home configuration.";
	echo "========================================================================";
	echo "Options:";
	echo "By default it only shows what is going to be done."
	echo "Set dry_run=false to actually carry out the commands.";
	echo;
	echo "Examples:";
	echo "bash $0 check";
	echo "bash $0 preinst dry_run=false";
	echo "bash $0 systemconf dry_run=false";
	echo "bash $0 userconf dry_run=false";
}

#=======================================================================
#Pre-Boot
#=======================================================================
function make_usb() {
	if [ `net_connected` == 1 ];then echo "Internet connected.";else echo "Internet disconnected.";fi;

	#download or use existing iso #if $arch_iso is set a path and the path isn;t invalid, #does not verify signature
	if [ "$arch_iso" != "" ] && [ -f "$arch_iso" ]; then echo "Found ISO: $arch_iso";
	else
		echo "Cannot find ISO...Downloading...";
		get_iso;
	fi;

	#same for signature
	if [ "$arch_sig" != "" ] && [ -f "$arch_sig" ]; then echo "Found SIG: $arch_sig";
	else
		echo "Cannot find SIG...Downloading...";
		get_sig;
	fi;

	#verify
	echo "Verifying signature...";
	if [ $verify_iso == true ] && [ -f $arch_iso ] && [ -f $arch_sig ];
	then
		verify_iso "$arch_sig";
	fi;

	if [ "`ask_for_value "Function to write the USB is not fully functional yet. Continuing might harm the USB drive. Continue?(y/N) :"`" != "Y" ];
	then
		exit;
	fi;

	#write iso to usb
	echo "Writing iso to $DEV_USB...";
	#cannot locate iso
	if [ $dry_run == false ] && [ ! $arch_iso ];then echo "Cannot find iso. Aborting..."; exit; fi;
	#cannot find usb
	if [ $dry_run == false ] && [ "$DEV_USB" == "" ];then echo "Cannot find dev/USB/. Aborting..."; exit; fi;
	#usb already mounted
	if [ "$DEV_USB" != "" ] && [ `mount | grep -o "$DEV_USB"` ]; then echo "$DEV_USB is mounted. Unmount and retry."; exit; fi;
	#cannot determine block_size
	if [ ! $block_size ];then echo "setting block_size=4M."; block_size="4M"; fi;
	#write usb
	echo "Writing $arch_iso image to $DEV_USB with bs=$block_size. Please wait patiently...";
	if [ $dry_run == false ];
	then
		sudo dd if="$arch_iso" of="$DEV_USB" bs="$block_size"; fi; #to check status # killall -USR1 dd
	echo "Finished writing $DEV_USB.";

	#wait till completes - unplug usb and plug it in device to be installed.

	#TODO: get script embedded in image somehow > immediately usable after boot

	#cleanup
}
#=======================================================================
#Pre-Installation
#=======================================================================
function preinst() {
	#check if root, cannot be run as user
	needsudo;

	#check configuration
	#if no preset found, run config_wiz
	[[ $run_config_wiz ]] && config_wiz "preinst";
	check_config "preinst" | less;

	if [ "`ask_for_value "Continue with this configuration?(y/N)"`" != "Y" ]; then exit; fi;
	#no point running if no internet
	if [ `net_connected` != 1 ]; then echo "Please configure internet before running bash $0 preinst dry_run=$dry_run."; exit 1; fi;

	#set time
	print_block "Setting localtime to $time_zone/$time_subzone";
	set_time;

	print_block "Beginning installation ...";
	if [ "$kb_layout" != "" ]; then echo "Loading Keyboard layout - $kb_layout"; fi;
	if [ $dry_run == false ];then loadkeys "$kb_layout" || loadkeys defkeymap; fi; #more in /usr/share/kbd/keymaps/

	#run efi check, exit if UEFI i.e return status = 0
	check_efi && exit 1;

	#set mirrors using rankmirrors #consumes quite a lot of time
	if [ "`ask_for_value "Update repo servers in pacman mirrorlist?(Y/n)"`" == "Y" ];
	then
		print_block "Generating mirrors by their speed using rankmirror ..."
		if [ $dry_run == false ];
		then
			rank_mirrors_by_speed;
			echo "Showing top-15 servers:";
			cat /etc/pacman.d/mirrorlist | grep "Server" | head -n 15;
			sleep 5;
		fi;
	fi;

	#mounts
	print_block "Mounting the drives ...";
	run_mounts;
	print_block "Finished mounting.";

	#run pacstrap
	print_block "Running pacstrap using /mnt ($mount_root) as / .";
	if [ $dry_run == false ];
	then pacstrap -i /mnt $strap_pkgs; fi;
	echo "Finished base installation on /mnt ";

	#generate fstab
	echo "Generating fstab in /mnt/etc/";
	if [ $dry_run == false ];
	then genfstab -p "/mnt" >> "/mnt/etc/fstab"; fi;

	#copy script to chrooted arch for postinst()
	echo "Copying script to / for postinst..";
	if [ $dry_run == false ];
	then cp "$0" "/mnt/"; fi;

	#chroot and run post-installation
	print_block "Chrooting to /mnt/ for post-installation configurations ...";
	if [ $dry_run == false ];
	then arch-chroot "/mnt" "$user_shell" "$0" "postinst" "dry_run=$dry_run"; #remove path-to-bash to drop into sh prompt #$0 is ./archinst.sh --> installscript. #passed value of dry_run
	else #demo - dry_run=true
		postinst; #otherwise start postinst with dry_run=true
	fi;

	#confirm and reboot when control returns after postinst finishes
	if [ "`ask_for_value "Would you like to Unmount & reboot(Recomended)?(Y/n)"`" == "Y" ];
	then
		print_block "Unmounting drives then reboot ";
		echo "Unmounting /mnt/";
		if [ $dry_run == false ]; then umount -R /mnt/; fi;
		echo "Reboot in 5...";
		echo "After reboot run script again with systemconf to configure system..";
		if [ $dry_run == false ]; then sleep 5; reboot; fi;
	fi;
}
#=======================================================================
#Post Installation configurations
#=======================================================================
function postinst() {
	#check if root, cannot be run as user
	needsudo;

	#check configuration
	#if no preset found, run config_wiz
	[[ $run_config_wiz ]] && config_wiz "postinst";
	check_config "postinst" | less;

	if [ "`ask_for_value "Continue with this configuration?(y/N)"`" != "Y" ]; then exit; fi;

	print_block "Beginning Post Installation ...";
	#hostname
	echo "Setting hostname: $hostname";
	#if [ $dry_run == false ]; then hostnamectl set-hostname "$hostname"; fi;
	if [ $dry_run == false ]; then echo "$hostname" > /etc/hostname; fi;

	#set password
	echo "Set root password...";
	if [ $dry_run == false ]; then passwd; fi;

	#generate locales
	echo "Generating Locales: ${gen_locales[*]}";
	if [ $dry_run == false ]; then generate_locales; fi;

	#set time
	echo "Setting timezone to $time_zone/$time_subzone and hwclock to UTC.";
	if [ $dry_run == false ]; then set_time; fi;

	#setting console keymap
	echo "KEYMAP=$kb_layout" > /etc/vconsole.conf;
	echo "FONT=Lat2-Terminus16" >> /etc/vconsole.conf;

	#retain boot messages
	echo "Setting up TTY1 to retain boot messages.";
	if [ $dry_run == false ];
	then
		mkdir -p "/etc/systemd/system/getty@tty1.service.d/";
		echo "[service]" > "/etc/systemd/system/getty@tty1.service.d/noclear.conf";
		echo "TTYVTDisallocate=no" >> "/etc/systemd/system/getty@tty1.service.d/noclear.conf";
	fi;

	#generate ramdisk
	print_block "Generating initial ramdisk ...";
	if [ $dry_run == false ]; then mkinitcpio -p linux; fi;

	#grub
	print_block "Installing bootloader (grub2) to device: $grub_device ...";
	if [ -b "$grub_device" ];
	then
		if [ $dry_run == false ];
		then
			grub-install --target=i386-pc --recheck --debug "$grub_device";
			cp /usr/share/locale/en\@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo; #in case missing locale
			grub-mkconfig -o /boot/grub/grub.cfg;
		fi;
	else echo "Cannot find $grub_device";
	fi;

	#adding user
	print_block "Creating and configuring user ...";
	echo "Creating user(group: $user_grtype): $user_name, shell: $user_shell";
	echo "Adding $user_name to groups: $user_gradd";
	if [ $dry_run == false ];
	then useradd -m -g "$user_grtype" -G "$user_gradd" -s "$user_shell" "$user_name";
	fi;
	echo "Creating password for user: $user_name";
	if [ $dry_run == false ]; then passwd "$user_name"; fi;

	#give sudo privileges to group: wheel
	echo "Give sudo privilege to users in group: 'wheel'";
	if [ $dry_run == false ]; then sleep 5; EDITOR=nano visudo; fi; #uncomment %wheel ALL=(ALL) ALL
	#add user to group # gpasswd -d to remove
	#gpasswd -a $username $groups #or #usermod -aG additional_groups username

	#move script to user directory for systemconf and change ownership to user
	print_block "Copying script to /home/$user_name/ for system configuration later ...";
	if [ $dry_run == false ];
	then
		mv "$0" /home/"$user_name"/;
		chown "$user_name" "/home/$user_name/$0";
	fi;

	print_block "Finished installation . Exiting chroot..."; #goes back to preinst for reboot
	if [ $dry_run == false ]; then sleep 5; return 0; fi;
}
#=======================================================================
#Configure system
#=======================================================================
function systemconf() {
	#login as user #must have sudo
	#check if root, cannot be run as user
	needsudo;
	#check configuration
	#if no preset found, run config_wiz
	[[ $run_config_wiz ]] && config_wiz "systemconf";
	check_config "systemconf" | less;

	if [ "`ask_for_value "Continue with this configuration?(y/N)"`" != "Y" ]; then exit; fi;

	#no point running if no internet
	if [ `net_connected` != 1 ]; then echo "Please configure internet before running sudo bash $0 systemconf."; exit 1; fi;

	print_block "Beginning user system installation...";

	#check else enable multilib in /etc/pacman.conf
	if [ `grep "#\[multilib\]" /etc/pacman.conf` ];
	then
		echo "Uncomment multilib in pacman.conf"; sleep 5;
		if [ $dry_run == false ]; then nano /etc/pacman.conf; fi;
	else echo "Multilib alread enabled in /etc/pacman.conf";
	fi;

	#basic firewall setup
	print_block "Setting up firewall - iptables ";
	if [ $dry_run == false ];
	then
		setup_iptables;
	fi;

	#install system packages
	print_block "Beginning system packages install ";
	install_packages "${install_pkgs_system[*]}";

	#services
	if [ $? == 0 ]; #check status of install_packages enable servies if it completed successfully
	then
		print_block "Enabling system services ...";
		#start services
		start_service ${services_system[*]};
		#for serv in ${services_system[*]};
		#do
		#	start_service "$serv";
		#done;

		if [ `ask_for_value "Initiate rkhunter database??"` == "Y" ];
		then
			print_block "Running initial scans...";
			#rkhunter check version / update / set default props
			echo "Setting up rkhunter rootkit checker...";
			if [ $dry_run == false ];
			then
				rkhunter --versioncheck;
				rkhunter --update;
				rkhunter --propupd;
				#sudo rkhunter -c --enable all --disable none #to start testing binaries
			fi;
		fi;

		#lm_sensors
		echo "Detecting CPU sensors...";
		if [ $dry_run == false ]; then sensors-detect --auto; fi;
	else
		echo "Cannot enable servies/run checks without packages installed.";
	fi;

	print_block "Beginning user package installation ...";
	install_packages "${install_pkgs_user[*]}";

	#services
	if [ $? == 0 ]; #check status of install_packages enable servies if it completed successfully
	then
		print_block "Enabling user services ...";
		#start services
		for serv in ${services_user[*]};
		do
			start_service "$serv";
		done;

		#add optirum user to group bumblebee here

	else
		echo "Cannot enable servies/run checks without packages installed.";
	fi;

	#index file locations for locate
	print_block "Updating file location database.";
	if [ $dry_run == false ]; then updatedb; fi;

	print_block "Finished system installation. For user configuration run userconf with user privileges.";
}
#=======================================================================
#Configure user
#=======================================================================
function userconf() {
	#check if user, cannot be run as root
	if (( $UID != 1000 )); then print_block "Cannot run without being user. Exiting."; exit 1; fi;

	#check configuration
	#if no preset found, run config_wiz
	[[ $run_config_wiz ]] && config_wiz "userconf";
	check_config "userconf" | less;

	if [ "`ask_for_value "Continue with this configuration?(y/N)"`" != "Y" ]; then exit; fi;

	#no point running if no internet
	if [ `net_connected` != 1 ]; then echo "Please configure internet before running userconf."; exit 1; fi;

	print_block "Beginning user configurations...";

	#generate ssh keys
	print_block "Generating public/private keypairs ...";
	if [ $dry_run == false ];then generate_sshkeys; fi;

	#build and install yaourt #needs curl
	print_block "Building and installing Yaourt from AUR ..."
	if [ $dry_run == false ];
	then
		curdir=`pwd`;
		mkdir /tmp/yaourt; #erased at reboot
		cd /tmp/yaourt;
		curl -O https://aur.archlinux.org/packages/pa/package-query/package-query.tar.gz;
		tar zxvf package-query.tar.gz;
		cd ./package-query;
		makepkg -si;
		cd ..;
		curl -O https://aur.archlinux.org/packages/ya/yaourt/yaourt.tar.gz;
		tar zxvf yaourt.tar.gz;
		cd ./yaourt;
		makepkg -si;
		cd "$curdir"; #return ~
	fi;

	#update yaourt db
	#echo "Updating yaourt database...";
	#if [ $dry_run == false ]; then yaourt -Syua; fi;

	#install AUR packages here
	echo "Updating yaourt database and installing packages from AUR...";
	echo "Packages: ${install_pkgs_aur[*]}";
	if [ $dry_run == false ]; then yaourt -Syua ${install_pkgs_aur[*]}; fi;

	#git -setting up dotfiles
	print_block "Setting up user config files from $user_config_git..."
	if [ $dry_run == false ];
	then
		git clone "$user_config_git";
		#sh ./dotfiles/linkthedots.sh push;
	fi;

	#Finish
	print_block "Finished installation.";
	#reboot
	if [ "`ask_for_value "Would you like to reboot?(Y/n)"`" == "Y" ];
	then
		echo "Reboot in 5...";
		if [ $dry_run == false ]; then sleep 5; reboot; fi;
	fi;
	return 0;
}
#=======================================================================
#CLI
#=======================================================================
function cli() {
	case "$1" in
	#functions
	"netcheck")
		if [ `net_connected` == 1 ];then echo "Internet connected.";
		else
			echo "Internet disconnected.";
			echo "If only startng with installation, run:";
			echo "    (bash) $0 networker";
			echo "else use wicd-curses or wicd-gtk to setup networks".
		fi;
	;;
	"getscript") get_script;
	;;
	"getiso") get_iso;
	;;
	"getsig") get_sig;
	;;
	"verify")
		shift;
		verify_iso "$1";
	;;
	"networker") networker;
	;;
	"rankmirrors") rank_mirrors_by_speed;
	;;
	"mount") run_mounts;
	;;
	"genlocale") generate_locales;
	;;
	"settime") set_time;
	;;
	"firewall") setup_iptables;
	;;
	"pacinst")
		shift;
		install_packages "$@";
	;;
	"startservice")
		shift;
		start_service "$@";
	;;
	"genssh") generate_sshkeys;
	;;
    "check")#if no preset found, run config_wiz
			[[ $run_config_wiz ]] && config_wiz "showall";
			check_config "showall" | less;
    ;;
	#procedures
	"make_usb") make_usb;
	;;
	"preinst") preinst;
	;;
	"postinst") postinst;
	;;
	"systemconf") systemconf;
	;;
	"userconf") userconf;
	;;
	*)
		show_usage;
	;;
	esac;
}
#=======================================================================
#TESTS
#=======================================================================
#print_block "lol" "kol" "bol"
#get_rootdir;
#net_connected;
#get_iso;
#echo $arch_iso;
#get_sig;
#echo $arch_sig;
#verify_iso $arch_sig;
#networker;
#rank_mirrors_by_speed;
#set_time;
#generate_locales;
#generate_sshkeys;
#echo ${ipt_openports[*]};
#setup_iptables;
#echo "$hostname";
#echo "PKGSYS: ${install_pkgs_system[*]}";
#echo;
#echo "SERVISYS: ${services_system[*]}";
#echo;
#echo "PKGUSR: ${install_pkgs_user[*]}";
#echo;
#echo "SERVIUSR: ${services_user[*]}";
#echo
#echo "PKGAUR: ${install_pkgs_aur[*]}";
#echo;
#echo "CONFGIT: $user_config_git";
#install_packages "${install_pkgs_system[*]}";
#echo $?;
#if [ "`ask_for_value "Would you like to reboot?(Y/n)"`" == "Y" ]; then echo "YES"; fi;
#mount_devices;
#needsudo;
#start_service "${services_system[*]}";
#yaourt -Syua ${install_pkgs_aur[*]};
#exit;
#=======================================================================
#RUN
#=======================================================================
#if not in bash shell, start bash shell
if [ "$SHELL" != "/bin/bash" ];
then
	echo "Please run script in shell: /bin/bash";
fi;

#append "dry_run=true or false" at the end of args to toggle dry_run
if [ "`echo $@ | grep -ow "dry_run=true"`" != "" ]; then dry_run=true;fi;
if [ "`echo $@ | grep -ow "dry_run=false"`" != "" ]; then dry_run=false;fi;
echo "Dry_Run=$dry_run";sleep 1;

#show preset prompt if THOSE FUNCTIONS are run
select_preset "$1";

#pass arguments to cli
cli "$@";
