
# expand disk in VM(host has to be turned off); dir space will be resized
expand( dir, size? ):
    die if dir doesnt exist;
    map->(dir, size): return-> $disk, $vg, $lv
    create partition on disk
    lvm->($disk, $vg, $lv, $dir, $size)

# add new disk in VM, dir space will be resized by extending vg lv on new partition, mounted on existing dir 
extend( dir, disk, size? ):
    die if dir doesnt exist;
    check if disk exist, if doesnt refresh
        die if disk doesnt exist
    map->(mountpoint, size?): return-> $disk, vg, lv of /dir
    
    if there is space for partition on other disk where /dir is already mounted offer disk names option
    create partition on chosen disk
    lvm

# create new mountpoint, vg, lv on existing/new disk
new( dir, disk, vg, lv, size? )
    die if dir exist # if i create new lv on existing vg and mount it on existing dir, space of dir equals only to size of new lv. unmounting new lv_path (umount /dev/mapper/vg_existing-lv_new) will switch back size of dir to old size; mounting new lv_path again will restore content of new lv (this  works only  when there is entry in /etc/fstab (/dev/vg_existing-lv_new /dir ext4 defaults 0 1); not implementing for now

    check if disk exist, if doesnt refresh
        die if disk still doesnt exist
    create partition on disk
    lvm

---

1..3
/dev/sdc  49392123904
/dev/sdd  21474836480
$VAR1 = {
          '/A' => {
                    'disks' => {
                                 'sdd' => {
                                            'part' => [
                                                        {
                                                          'path' => '/dev/sdd1',
                                                          'type' => 'Extended'
                                                        },
                                                        {
                                                          'path' => '/dev/sdd5',
                                                          'type' => 'LVM'
                                                        }
                                                      ],
                                            'path' => '/dev/sdd',
                                            'name' => 'sdd',
                                            'extended' => '/dev/sdd1'
                                          },
                                 'sdc' => {
                                            'part' => [
                                                        {
                                                          'type' => 'Extended',
                                                          'path' => '/dev/sdc1'
                                                        },
                                                        {
                                                          'path' => '/dev/sdc5',
                                                          'type' => 'LVM'
                                                        },
                                                        {
                                                          'type' => 'LVM',
                                                          'path' => '/dev/sdc6'
                                                        }
                                                      ],
                                            'extended' => '/dev/sdc1',
                                            'name' => 'sdc',
                                            'path' => '/dev/sdc'
                                          }
                               },
                    'pv_choose' => {
                                     '/dev/sdd' => '21474836480'
                                   },
                    'dir' => '/A',
                    'lv_path' => '/dev/mapper/vg_a-lv_b',
                    'vg' => 'vg_a',
                    'pv' => [
                              '/dev/sdb5',
                              '/dev/sdb6',
                              '/dev/sdc5',
                              '/dev/sdc6',
                              '/dev/sdd5'
                            ],
                    'lv' => 'lv_b'
                  }
        };

__DATA__

in VMWare add new disk 5G
reboot linux
lsblk will show new disk with NAME sdc (if sda and sdb exist.. every new disk uses next letter in alphabet as last letter )

create partition sdc1 for full current space 5G (fdisk /dev/sdc)
initialize pv to use with lvm (pvcreate /dev/sdc1)
create vg and add /dev/sdc1 partition (vgcreate vg_repodata /dev/sdc1;
create lv on sdc1 full extend to disk size(5G) and add it in vg  (lvcreate -n lv_big -l 100%FREE vg_repodata)
make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)
mount lv to mountpoint (mount /dev/vg_repodata/lv_big /big)
put in /etc/fstab (/dev/vg_repodata/lv_big /big ext4 defaults 0 1)

OTHER COMMANDS
remove PV
- first remove PV frmom VG (vgreduce vg_repodata /dev/sdb3)
- then remove PV from LVM (pvremove /dev/sdb3)

if doesnt work

- remove partition fdisk /dev/sdb
- remove PV (vgreduce --removemissing --force vg_repodata)

----
extend existing disk in vm to 7G and reboot OR add new disk in vm and to see changes in host do (for i in `ls -tr  /sys/class/scsi_host/`;do echo "- - -" > /sys/class/scsi_host/$i/scan;done) 


sdc                      8:16   0    7G  0 disk
└─sdc1                   8:17   0    5G  0 part
  └─vg_repodata-lv_big 252:0    0    5G  0 lvm
----

create partition sdc2 for remainging space 2G
initialize pv to use with lvm (pvcreate /dev/sdc2)
force kernel to use new part table (partprobe /dev/sdc)
Add this pv to vg_tecmint vg to extend the size of a volume group to get more space for expanding lv(vgextend vg_tecmint /dev/sda2)
check available Physical Extends( available Physical Extend )
expand lv(lvextend -l +4607 /dev/vg_repodata/lv_big)
resize fs (resize2fs /dev/vg_repodata/lv_big)

create lv vg on sdc2 full extend (2G)
???check fstype(df -T /big)
???make filesystem type (mkfs.ext4 /dev/vg_repodata/lv_big)

# http://unix.stackexchange.com/questions/199164/error-run-lvm-lvmetad-socket-connect-failed-no-such-file-or-directory-but
#system("systemctl enable lvm2-lvmetad.service && systemctl enable lvm2-lvmetad.socket && systemctl start lvm2-lvmetad.service && systemctl start lvm2-lvmetad.socket");
