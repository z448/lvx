
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
    die if dir exist
    check if disk exist, if doesnt refresh
        die if disk still doesnt exist
    create partition on disk
    lvm


---







