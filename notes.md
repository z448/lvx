
# expand disk in VM(host has to be turned off); dir space will be resized
expand( mountpoint, size? ):
    die if dir doesnt exist;
    map->(mountpoint, size)
    lvm

# add new disk in VM, dir space will be resized by extending vg lv on new partition, mounted on existing dir 
extend( mountpoint, disk, size? ):
    die if dir doesnt exist;
    check if disk exist, if doesnt refresh
        die if disk doesnt exist
    map->(mountpoint, size?) to get vg, lv of /dir
    create partition on disk
    lvm

# create new mountpoint, vg, lv on existing/new disk
new( mountpoint, vg, lv, disk, size? )
    die if dir exist
    check if disk exist, if doesnt refresh
        die if disk still doesnt exist
    create partition on disk
    lvm







