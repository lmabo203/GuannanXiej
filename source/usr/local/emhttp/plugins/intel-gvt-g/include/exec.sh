#!/bin/bash

function get_gvt_pci(){
echo -n "$(lspci -D | grep -E "VGA compatible controller|Display controller" | grep "Intel" | awk '{print $1}' | sort | tail -1)"
}

function get_gvt_adapter_name(){
echo -n "$(lspci -D | grep -E "VGA compatible controller|Display controller" | grep "Intel" | sort | tail -1 | awk '{print $1=$2=$3=$4=""; print $0}')"
}

function get_gvt_avail_modes(){
echo -n "$(ls /sys/devices/pci${1%:*}/$1/mdev_supported_types)"
}

function get_gvt_avail_vms(){
echo -n "$(virsh list --all --name)"
}

function assign_vm(){
PCIROOT=${2%:*}
#Check if qemu hooks file is backed up and back it up if not
if [ ! -f /etc/libvirt/hooks/qemu.orig ]; then
  cp /etc/libvirt/hooks/qemu /etc/libvirt/hooks/qemu.orig
fi
#Check if configuration for VM is already created and matches otherwise change it or create it
if grep "VM={${1//+/ }}" /boot/config/plugins/intel-gvt-g/vms.conf >&/dev/null ; then
  if ! grep "VM={${1//+/ }} {${3}}" /boot/config/plugins/intel-gvt-g/vms.conf >&/dev/null ; then
    sed -i "/VM={${1//+/ }}/c\VM={${1//+/ }} {$3} {"$(uuidgen)"}" /boot/config/plugins/intel-gvt-g/vms.conf
  fi
else
  echo -n "VM={${1//+/ }} {$3} {"$(uuidgen)"}
" >> /boot/config/plugins/intel-gvt-g/vms.conf
fi
#Check if VM is already in qemu hooks
if grep "if (\$argv\[1] == \"${1//+/ }\"){" /etc/libvirt/hooks/qemu >&/dev/null ; then
  sed -i '/if ($argv\[1] == "'"${1//+/ }"'"){/,+8d' /etc/libvirt/hooks/qemu
  sed -i '/\?php/a\
if ($argv[1] == "'"${1//+/ }"'"){\
        if ($argv[2] == \x27prepare\x27 && $argv[3] == \x27begin\x27){\
                shell_exec(\x27echo "$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "'"${1//+/ }"'" | awk -F\\\x27[{}]\\\x27 \\\x27{print $6}\\\x27)" > /sys/devices/pci'"${PCIROOT//:/'\\':}"'/'"${2//:/'\\':}"'/mdev_supported_types/'"${3}"'/create\x27);\
        }\
        if ($argv[2] == \x27release\x27 && $argv[3] == \x27end\x27){\
                shell_exec(\x27echo 1 > /sys/devices/pci'"${PCIROOT//:/'\\':}"'/'"${2//:/'\\':}"'/"$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "'"${1//+/ }"'" | awk -F\\\x27[{}]\\\x27 \\\x27{print $6}\\\x27)"/remove\x27);\
        }\
		sleep(2);\
}' /etc/libvirt/hooks/qemu
  /usr/local/emhttp/plugins/intel-gvt-g/include/exec.sh check_vm_xml ${1} "$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "${1//+/ }" | awk -F'[{}]' '{print $6}')"
else
  sed -i '/\?php/a\
if ($argv[1] == "'"${1//+/ }"'"){\
        if ($argv[2] == \x27prepare\x27 && $argv[3] == \x27begin\x27){\
                shell_exec(\x27echo "$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "'"${1//+/ }"'" | awk -F\\\x27[{}]\\\x27 \\\x27{print $6}\\\x27)" > /sys/devices/pci'"${PCIROOT//:/'\\':}"'/'"${2//:/'\\':}"'/mdev_supported_types/'"${3}"'/create\x27);\
        }\
        if ($argv[2] == \x27release\x27 && $argv[3] == \x27end\x27){\
                shell_exec(\x27echo 1 > /sys/devices/pci'"${PCIROOT//:/'\\':}"'/'"${2//:/'\\':}"'/"$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "'"${1//+/ }"'" | awk -F\\\x27[{}]\\\x27 \\\x27{print $6}\\\x27)"/remove\x27);\
        }\
		sleep(2);\
}' /etc/libvirt/hooks/qemu
  /usr/local/emhttp/plugins/intel-gvt-g/include/exec.sh check_vm_xml ${1} "$(cat /boot/config/plugins/intel-gvt-g/vms.conf | grep "${1//+/ }" | awk -F'[{}]' '{print $6}')"
fi
}

function check_vm_xml(){
if grep "        <address uuid=" /etc/libvirt/qemu/"${1//+/ }".xml >&/dev/null ; then
  sed -i "/        <address uuid=/c\        <address uuid='${2}'/>" /etc/libvirt/qemu/"${1//+/ }".xml
  virsh define /etc/libvirt/qemu/"${1//+/ }".xml
  sleep 1
else
  sed -i '/<memballoon model=/i\    <hostdev mode=\x27subsystem\x27 type=\x27mdev\x27 managed=\x27no\x27 model=\x27vfio-pci\x27 display=\x27off\x27>\
      <source>\
        <address uuid='"'"${2}"'"'/>\
      </source>\
    </hostdev>' /etc/libvirt/qemu/"${1//+/ }".xml
  virsh define /etc/libvirt/qemu/"${1//+/ }".xml
  sleep 1
fi
}

function get_avail_vm_assignments(){
echo -n "$(cat /boot/config/plugins/intel-gvt-g/vms.conf | awk -F'[{}]' '{print $2" with mode "$4}')"
}

function delete_vm_assignment(){
VM_NAME="${1%+with*}"
sed -i '/VM={'"${VM_NAME//+/ }"'} {'"${1#*+mode+}"'}/d' /boot/config/plugins/intel-gvt-g/vms.conf
sed -i '/if ($argv\[1] == "'"${VM_NAME//+/ }"'"){/,+8d' /etc/libvirt/hooks/qemu
if [ ! -s /boot/config/plugins/intel-gvt-g/vms.conf ]; then
  rm -rf /boot/config/plugins/intel-gvt-g/vms.conf
fi
sed -i "/    <hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='off'>/,+5d" /etc/libvirt/qemu/"${VM_NAME//+/ }".xml
virsh define /etc/libvirt/qemu/"${VM_NAME//+/ }".xml
}

function get_guc_huc_mode(){
echo -n "$(cat /boot/config/plugins/intel-gvt-g/settings.cfg | grep "guc_huc_mode=" | cut -d '=' -f2)"
}

function set_guc_huc(){
sed -i "/guc_huc_mode=/c\guc_huc_mode=${1}" "/boot/config/plugins/intel-gvt-g/settings.cfg"
/usr/local/emhttp/plugins/dynamix/scripts/notify -e "Intel-GVT-g" -d "Please reboot to apply the new mode for GuC/HuC firmware loading!" -l "/Main"
}

function restore_qemu_cfg(){
cp /etc/libvirt/hooks/qemu.orig /etc/libvirt/hooks/qemu
}

$@
