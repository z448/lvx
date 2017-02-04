
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

$disk->('sdb',size?)
$VAR1 = {
          'path' => '/dev/sdb',
          'name' => 'sdb',
          'extended' => '/dev/sdb1',
          'part' => [
                      {
                        'type' => 'Extended',
                        'path' => '/dev/sdb1'
                      },
                      {
                        'path' => '/dev/sdb5',
                        'type' => 'LVM'
                      },
                      {
                        'type' => 'LVM',
                        'path' => '/dev/sdb6'
                      }
                    ]
        };


---
$map->('/A',size?)
$VAR1 = {
          'vg' => 'vg_a',
          'disk_size' => ' 34G',
          'lv_size' => ' 20G',
          'dir' => '/A',
          'lv' => 'lv_a',
          'lv_path' => '/dev/mapper/vg_a-lv_a',
          'disk' => '/dev/sdb',
          'pv_choose' => {
                           '/dev/sdb' => '6'
                         },
          'disks' => {
                       '/dev/sdb' => '6'
                     },
          'pv' => [
                    '/dev/sdb5',
                    '/dev/sdb6'
                  ]
        };


---

$VAR1 = {
          '/A' => {
                    'lv' => 'lv_a',
                    'vg' => 'vg_a',
                    'disks' => {
                                 'sdb' => {
                                            'part' => [
                                                        {
                                                          'type' => 'Extended',
                                                          'path' => '/dev/sdb1'
                                                        },
                                                        {
                                                          'type' => 'LVM',
                                                          'path' => '/dev/sdb5'
                                                        },
                                                        {
                                                          'type' => 'LVM',
                                                          'path' => '/dev/sdb6'
                                                        }
                                                      ],
                                            'name' => 'sdb',
                                            'extended' => '/dev/sdb1',
                                            'path' => '/dev/sdb'
                                          },
                                 'sdc' => {
                                            'part' => [
                                                        {
                                                          'path' => '/dev/sdc1',
                                                          'type' => 'Extended'
                                                        },
                                                        {
                                                          'path' => '/dev/sdc5',
                                                          'type' => 'LVM'
                                                        }
                                                      ],
                                            'name' => 'sdc',
                                            'extended' => '/dev/sdc1',
                                            'path' => '/dev/sdc'
                                          }
                               },
                    'lv_path' => '/dev/mapper/vg_a-lv_a',
                    'dd' => 'sdc',
                    'pv_choose' => {
                                     '/dev/sdb' => '6'
                                   },
                    'disk_size' => ' 34G',
                    'dir' => '/A',
                    'lv_size' => ' 20G',
                    'pv' => [
                              '/dev/sdb5',
                              '/dev/sdb6',
                              '/dev/sdc5'
                            ],
                    'disk' => '/dev/sdb'
                  }
        };

