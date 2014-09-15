#!/bin/sh
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
#
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
#configuration options
#=======================================================================
#these are default or common values, to set values according too device
#setup devices according to their hostname in devices section

dry_run=true; #script doesnt do anything, but says it does.
debug=true; #ask before every step #not yet implemented

#source of script
scriptsrc=""
#-----------------------------------------------------------------------
#device exclusive configs are loaded according to the hostname set below.. [hostname must exist in devices!!]
#-----------------------------------------------------------------------
hostname="laptop";
#-----------------------------------------------------------------------
#stage=preboot - writing the usb device
#-----------------------------------------------------------------------
#arch version - latest
arch_mirror="http://mirror.cse.iitk.ac.in/archlinux/iso/2014.09.03/"; #indian mirror
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
kb_layout="us"; #keyboard layout

#internet - wired - dhcp - wifi -  used by networker() - better use wicd-curses in all cases except preinstallation
net_connection_type="wired"; # "wired" / "wifi"
net_interface="";
ip_type="dhcp"; # "dhcp" or "static"

#static addresses - leave blank if dhcp
if [ "$ip_type" == "static" ];
then
	net_ip="" ;				#e.g "192.168.1.101";
	net_mask=""; 			#e.g "/24"; #CIDR #mind the slash
	net_broadcast="";		#e.g "192.168.1.255";
	net_gateway=""; 		#e.g 192.168.1.1";
	net_nameserver=""; 		#e.g 192.168.1.1"; #DNS server
fi;

#-----------------------------------------------------------------------
#mounts - change here form custom mountpoints like /data/home or set them in devices
#-----------------------------------------------------------------------
#REQUIRED
mount_root="";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;
#optional
mount_swap="";
#optional
mount_home="";mountpoint_home="/mnt/home";fstype_root="ext4";format_home=true;
#optional
mount_boot="";mountpoint_boot="/mnt/boot";fstype_boot="fat";format_boot=false;
#optional
mount_var="";mountpoint_var="/mnt/var";fstype_var="ext4";format_var=true;
#optional
mount_etc="";mountpoint_etc="/mnt/etc";fstype_etc="ext4";format_etc=true;
#optional
mount_usr="";mountpoint_usr="/mnt/usr";fstype_usr="ext4";format_usr=true;

#grub install device
grub_device="";

#packages to install while pacstrap
strap_pkgs="base base-devel grub os-prober wicd"; #dialog wpa_supplicant if using wifi-menu/netctl/networkmanager later
#-----------------------------------------------------------------------
#stage=postinst
#-----------------------------------------------------------------------
#locales
gen_locales=(
#	"en_IN.UTF-8"
	"en_US.UTF-8"
	"en_GB.UTF-8"
);
#systime
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
#	"linux-lts" #long-term-supported kernel #breaks much less
	"htop wget lsof bc ntp hdparm"
	"openssh sshfs" #sshfs or fuse itself, however only this one needed mostly
	"p7zip rkhunter dosfstools mlocate" #rkhunter=rootkit checker #mlocate=file locator
	"acpid cpupower lm_sensors" #cpuscaling and powermon #view sensor data lm_sensors
	"alsa-utils alsa-plugins" #alsa
	"git" #vcs
);

#services to start after systemconf
services_system=("cpupower.service" "sshd.service" "wicd.service");

#optional package groups - installed by user
#xorg
opt_pkgs_x11="xorg-server xorg-apps xorg-xinit xorg-server-utils xterm"; #xorg-server + apps + utils + xterm
#graphics drivers
opt_pkgs_gfx_intel="xf86-video-intel lib32-intel-dri"; #intel drivers
opt_pkgs_gfx_nvidia="bumblebee bbswitch primus virtualgl lib32-primus lib32-virtualgl intel-dri nvidia lib32-nvidia-utils" #nvidia card + intel dri (laptop)
#fonts
opt_pkgs_font="ttf-dejavu ttf-inconsolata terminus-font";
#sound server: pulseaudio+alsa
optional_pkgs_pulseaudio="pulseaudio paprefs pavucontrol pulseaudio-alsa lib32-libpulse lib32-alsa-plugins";
#vbox
opt_pkgs_vbox="virtualbox qt4 virtualbox-host-dkms linux-headers virtualbox-guest-iso"; #enable dkms.service from systemctl and modprobe vboxdrv before loading guests
#office suite - libreoffice
opt_pkgs_libreoffice="libreoffice-fresh libreoffice-fresh-en-GB libreoffice-still-gnome";
#XMPP+irc - pidgin
opt_pkgs_pidgin="pidgin pidgin-otr pidgin-encryption" #suspend needs a separate systemd unit https://wiki.archlinux.org/index.php/Pidgin

#common packages
install_pkgs_user=( #if the device needs specific packages or drivers, specify in devices giving it a seperate name
	#gui sudo
		"gksu"
	#clipboard
		"xclip"
	#display server: x
		"$opt_pkgs_x11"
	#screensaver
	#	"xscreensaver"
	#compositor
	#	"xcompmgr" #compton
	#wm + themes
		"awesome"
		"lxappearance numix-themes elementary-icon-theme xcursor-vanilla-dmz" #GTKthemes/icons/cursor
	#mouse
		"gpointing-device-settings"
	#gui networks
		"wicd-gtk"
	#fonts
		"$opt_pkgs_font"
	#sound
		"$optional_pkgs_pulseaudio"
	#disk util
		"gnome-disk-utility"
	#files
		"pcmanfm xarchiver udisks" #files + automount + archive gvfs
		"zip unzip unrar"
	#pic viewer
		"viewnior" #gpicview
	#	"geeqie" #for raw files
	#gui text editor
		"beaver"
	#IDE
	#	"geany"
	#pdf reader
		"evince"
	#music player
		"cmus"
	#video player
		"mpv" #whaawmp / vlc
	#internet
		"firefox" #chromium for plebs
	#python
		"python2" #2.7.x #python for 3.x.x
);

services_user=();

#firewall - iptables open ports
#ipt_openports=("loopback" "established" "ssh" "avahi" "transmission-daemon" 
				#"mpd" "http" "https" "dns" "ping/pingblock/pinglimit" "synblock" "ftpbrute");
ipt_openports=("loopback" "established" "ssh" "ping");

#AUR packages
install_pkgs_aur=("sublime-text" "ttf-win7-fonts"); #acpi_call thermald pulseaudio-ctl #flashplugin -> shumway(aur)

#user config git - separate script to push the files (linkthedots.sh)
user_config_git="";

#=======================================================================
#device exclusive settings / packages
#=======================================================================
if [ "$hostname" == "laptop" ];
then
	#mounts
	#REQUIRED
	mount_root="";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;
	#optional
	mount_swap="";
	#optional
	mount_home="";mountpoint_home="/mnt/home";fstype_root="ext4";format_home=true;

	#grub
	grub_device="";

	#pacman packages
	install_pkgs_user+=(
	#battery
		"acpi" #acpid client
	#	"pm-utils powertop" #checkout tlp
	#graphics driver
		"$opt_pkgs_gfx_intel"
		"$opt_pkgs_gfx_nvidia" #	#add user to group bumblebee-> gpasswd -a "$user_name" bumblebee;
	#touchpad
		"xf86-input-synaptics"
	#audio player
	#	""	
	#torrent
		"transmission-gtk"
	#office
		"$opt_pkgs_libreoffice"
	);
	
	#services
	services_user+=("bumblebeed")
	
	#AUR packages
	install_pkgs_aur+=()
	
	#user config src - git repo
	user_config_git="";

elif [ "$hostname" == "desktop" ];
then
	#mounts
	#REQUIRED
	mount_root="/dev/sda1";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;
	#optional
	mount_swap="/dev/sda3";
	#optional
	mount_home="/dev/sda4";mountpoint_home="/mnt/home";fstype_root="ext4";format_home=true;

	#grub
	grub_device="/dev/sda";

	#pacman packages
	install_pkgs_user+=(
	#graphics driver
		"$opt_pkgs_gfx_intel"
	#audio player
		"mpd mpc ncmpcpp"
	#torrent
		"transmission-cli" #set runtime user in systemd units..config from git
	#virtual box
	#	"$opt_pkgs_vbox"
	#music organizer
	#	"beets" #needs python, mutagen
	#audio converter-> flac
	#	"sox"
	
	#	"mutagen hachoir-core hachoir-metadata" #meta viewer (python)
	#	"python2-pillow" #image editing library
	);
	
	#services
	services_user+=("dkms")

	#AUR packages
	install_pkgs_aur+=()
	
	#user config src - git repo
	user_config_git="";

elif [ "$hostname" == "desktopvm" ];
then
	#mounts
	#REQUIRED
	mount_root="";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;

	#grub
	grub_device="";

	#pacman packages
	install_pkgs_user+=(
	#graphics driver
		"$opt_pkgs_gfx_intel"
	#audio player
		"mpd mpc ncmpcpp"
	#torrent
		"transmission-cli"
	#music organizer
		"beets" #needs python, mutagen
	#audio converter-> flac
		"sox"
	
	#	"mutagen hachoir-core hachoir-metadata" #meta viewer (python)
	#	"python2-pillow" #image editing library
	);
	
	#services
	services_user+=()

	#AUR packages
	install_pkgs_aur+=()
	
	#user config src - git repo
	user_config_git="";

#elif [ "$hostname" == "" ];
#then
else #default config
	hostname="archlinux-`date  +%Y%m%d%H%M`";

	#mounts
	#REQUIRED
	mount_root="/dev/sda1";mountpoint_root="/mnt";fstype_root="ext4";format_root=true;

	#grub
	grub_device="`fdisk -l | grep -iwso "/dev/sd."`";
	#grub_device="/dev/sda";
fi;
#=======================================================================
#functions
#=======================================================================
function print_block() {
	echo "========================================================================";
	echo "$@";
	echo "[`date`]";
	echo "========================================================================";
	sleep 2;
}

function get_script() {
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
	#get rootdir
	filepath=`readlink -f $0`;
	rootdir="${filepath%/*}";
	echo $rootdir;
}

function net_connected() { #check if connected to internet
	#check internet
	ping -q -w 1 -c 1 8.8.8.8 > /dev/null && echo 1 || echo 0; #google dns
}

function ask_for_value() { #ask for value if value invalid #$1=prompt. # always returns capital
	read -p "$1" value;
	echo ${value^^};
}

function needsudo() { #check if have sudo privilege, else prompt and exit
	#check if root, cannot be run as user
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
		/usr/bin/wget -r -np http://"$arch_mirror" -A "$arch_isonamereg" -P $rootdir;
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
		/usr/bin/wget -r -np http://"$arch_mirror" -A "$arch_isonamereg.sig" -P $rootdir;
		#locate signature
		sigpath=`find $rootdir -name "$arch_isonamereg.sig" -type f`;
		echo "SIGpath: $sigpath";
		arch_sig="$sigpath";
	else
		echo "Set dry_run to false to start download.";
	fi;
}

function verify_iso() { #$1=/path/to/signature.sig
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

function rank_mirrors_by_speed() { #set mirrors using rankmirrors #needs su
	#check sudo
	needsudo;

	cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup;
	sed -i 's/^#Server/Server/' /etc/pacman.d/mirrorlist.backup; #uncomments every mirror
	rankmirrors /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist; #tests the mirrors and arranges by fastest
	echo "Finished generating mirrors."
}

function mount_device() { #args: $device $mountpoint $fstype $format_if_true #only used internally
	#return 1 if ""
	if [ "$1" == "" ]; then echo "Invalid block device"; return 1; fi;
	#if mountpoint does not exits - custom mountpoints like /data/home/
	if [ ! -d  "$2" ]; then mkdir -p "$2" || return $?; fi; 
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

function run_mounts() { #mount drives to their mount points
	#check sudo
	needsudo;

	#check if root, cannot be run as user
	if [ $dry_run == false ] && (( $EUID != 0 )); then print_block "Cannot run without being root. Exiting."; exit 1; fi;

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
		if [ `ask_for_value "If /boot/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_boot.Continue without a separate drive?(Y/n)"` != "Y" ];
		then 
			echo "Exiting...";
			exit 1;
		fi;
	fi;

	#home
	mount_device "$mount_home" "$mountpoint_home" "$fstype_home" "$format_home";
	if [ $? -gt 0 ];
	then 
		if [ `ask_for_value "If /home/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_home.Continue without a separate drive?(Y/n)"` != "Y" ];
		then 
			echo "Exiting...";
			exit 1;
		fi;
	fi;

	#etc
	mount_device "$mount_etc" "$mountpoint_etc" "$fstype_etc" "$format_etc";
	if [ $? -gt 0 ];
	then 
		if [ `ask_for_value "If /etc/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_etc.Continue without a separate drive?(Y/n)"` != "Y" ];
		then 
			echo "Exiting...";
			exit 1;
		fi;
	fi;

	#var
	mount_device "$mount_var" "$mountpoint_var" "$fstype_var" "$format_var";
	if [ $? -gt 0 ];
	then 
		if [ `ask_for_value "If /var/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_var.Continue without a separate drive?(Y/n)"` != "Y" ];
		then 
			echo "Exiting...";
			exit 1;
		fi;
	fi;

	#usr
	mount_device "$mount_usr" "$mountpoint_usr" "$fstype_usr" "$format_usr";
	if [ $? -gt 0 ];
	then 
		if [ `ask_for_value "If /usr/ drive is not specified or invalid, it will be created as just a directory at $mountpoint_usr.Continue without a separate drive?(Y/n)"` != "Y" ];
		then 
			echo "Exiting...";
			exit 1;
		fi;
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
	if [ "`ask_for_value "Continue with this configuration?(Y/n)"`" == "N" ]; 
	then
		echo "Exiting. Please manually mount atleast the root drive to /mnt and re-run script."
		exit 1;
	fi;
}

function networker() { #setup network. get values from config
	#check sudo
	needsudo;

	echo "Checking internet connection...";
	if [ `net_connected` == 0 ]; then echo "Internet connected"; return 0;
	#run wicd-curses if found
	elif [ `which "wicd-curses" > /dev/null && echo 1 || echo 0` == 1 ];
	then 
		echo "Starting wicd-curses.";
		if [ $dry_run == false ];
		then
			start_service wicd; #enable and start else restart
			wicd-curses;
		fi;
	#setup mnually - only for preinstallation
	else
		echo "Running manual setup...";
		#get interface
		if [ `ls "/sys/class/net" | grep -wo "$net_interface"` ]; then echo "Found interface $net_interface";
		else
			ip a;
			echo "[Info: lo* = loopback / e* = ethernet / w* = wlan]";																	
			read -p "Select interface exactly as shown above:" net_interface;
			echo "Found interface $net_interface";
		fi;
		#wired
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
				echo "Setting up static ip...";
				echo "Setting up static address on: $net_interface";
				echo "IP: $net_ip";
				echo "MASK: $net_mask";
				echo "BCAST: $net_broadcast";
				echo "GATEWAY: $net_gateway";
				echo "DNS: $net_nameserver";
				if [ $dry_run == false ];
				then
					#stop dhcp
					systemctl stop dhcpcd.service;
					#setup static ip
					ip link set dev "$net_interface" up;
					sudo ip addr add "$net_ip$net_mask" broadcast "$net_broadcast" dev "$net_interface";
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
	#check sudo
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
	localectl set-locale LANG="${gen_locales[0]}";
	localectl set-locale LC_COLLATE="C";
	localectl set-locale LC_TIME="${gen_locales[0]}";
	locale > /etc/locale.conf;
}

function set_time() { #setup localtime and hwclock #needs su
	#check sudo
	needsudo;

	if [ $dry_run == false ]; 
	then
		if [ -e "/etc/localtime" ]; then rm /etc/localtime; fi;
		ln -s /usr/share/zoneinfo/"$time_zone/$time_subzone" /etc/localtime;
		#set hardware clock to utc
		hwclock --systohc --utc;
	else
		echo "Time: `date`";
	fi;
}

function setup_iptables() { #firewall rules here #needs su
	#check sudo
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
	#check sudo
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
	#check sudo
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
			echo "Restarting $serv";
			if [ $dry_run == false ]; then systemctl restart "$serv";fi;
		else
			echo "Starting $serv";
			if [ $dry_run == false ]; then systemctl start "$serv"; fi;
		fi;
	done;
}

function generate_sshkeys() {
	if [ -f "$HOME/.ssh/id_rsa" ];
	then echo "Key exists."; exit 1;
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

function show_usage() {
	echo "Functions:";
	echo "========================================================================";
	echo "(bash) $0 netcheck	-> check internet connection";
	echo "(bash) $0 getscript	-> get latest version of script";
	echo "(bash) $0 getscript	-> download latest version of script.";
	echo "(bash) $0 getiso	-> download latest dual iso";
	echo "(bash) $0 getsig	-> download signature of latest release";
	echo "(bash) $0 verify ./.sig -> verify iso signature.";
	echo "(bash) $0 networker	-> setup network.";
	echo "(bash) $0 rankmirrors	-> rank repo mirrors by speed.";
	echo "(bash) $0 mount		-> mount devices as set in config.";
	echo "(bash) $0 genlocale 	-> generate locales defined in gen_locales.";
	echo "(bash) $0 settime	-> set timzone and hwclock as in config.";
	echo "(bash) $0 genssh	-> setup private/public keys.";
	echo "(bash) $0 firewall	-> setup iptables.";
	echo "(bash) $0 pacinst	-> install packaged listed after.";
	echo "(bash) $0 startservice	-> start or restart units listed after.";
	echo;
	echo "Usage:";
	echo "========================================================================";
	echo "(bash) $0 make_usb 	-> download and/or write usb.";
	echo "(bash) $0 preinst 	-> run installer upto chroot.";
	echo "(bash) $0 postinst 	-> run installer after chroot.";
	echo "(bash) $0 systemconf	-> user system configuration.";
	echo "(bash) $0 userconf	-> user home configuration.";
	echo "========================================================================";
	echo "Options:";
	echo "Set dry_run=false to actually carry out the commands.";
}
#=======================================================================
#Pre-Boot
#=======================================================================
function make_usb() {
	rootdir=`get_rootdir`;
	echo "Root: "$rootdir;

	#check net
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
exit;
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
	#no point running if no internet
	if [ `net_connected` != 1 ]; then echo "Please configure internet before running bash $0 preinst dry_run=$dry_run."; exit 1; fi;
	
	#set time 
	print_block "Setting localtime to $time_zone/$time_subzone";
	set_time;

	print_block "Beginning installation ...";
	if [ "$kb_layout" != "" ]; then echo "Loading Keyboard layout - $kb_layout"; fi;
	if [ $dry_run == false ];then loadkeys "$kb_layout"; fi; #more in /usr/share/kbd/keymaps/

	#check if efi
	print_block "Checking if UEFI...";
	if [ $dry_run == false ];
	then
		mount -t efivarfs efivarfs /sys/firmware/efi/efivars; # ignore if already mounted
		efivar -l;
		#if all listed correct then bootmode=uefi
		if [ $? == 0 ];
		then
			echo "Does not yet work with UEFI. Exiting..."; exit 1;
		else
			echo "Not UEFI. Continuing with installation...";
		fi;
	fi;

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
			echo "    (bash) $0 netoworker";
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
#append "dry_run=true or false" at the end of args to toggle dry_run
if [ "`echo $@ | grep -ow "dry_run=true"`" != "" ]; then dry_run=true;fi;
if [ "`echo $@ | grep -ow "dry_run=false"`" != "" ]; then dry_run=false;fi;
echo "Dry_Run=$dry_run";sleep 1;
cli "$@";