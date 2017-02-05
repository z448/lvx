
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

