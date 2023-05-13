#!/bin/sh

# Colors for whiptail
# Reference: https://askubuntu.com/questions/776831/whiptail-change-background-color-dynamically-from-magenta/781062#781062
export NEWT_COLORS='
  sellistbox=black,brightmagenta
  actsellistbox=black,brightmagenta
  actlistbox=black,brown
  listbox=black,
  window=,lightgray
  root=,gray
  title=brightred,
  actbutton=black,magenta
  button=black,red
'

# Find max length of element from an array
maxInArr() {
    arr=("$@")
    maxLength=${#arr[0]}
    for i in "${arr[@]:1}"; do
        if [ ${#i} -gt $maxLength ]; then
            maxLength=${#i}
        fi
    done
    return $maxLength
}
# Set termSize to size of terminal on calling time
calcTermSize() {
    IFS=' ' read -ra termSize <<< "$(stty size)"
    termSize[0]=$((termSize[0]-4))
    termSize[1]=$((termSize[1]-8))
}

# Store output of lsblk into 'lines' separated by "\n"
# lines -> NAME MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
IFS=$'\n' lines=($(lsblk -p -l))

mntPt=()
name=()
d_size=()
for i in "${lines[@]:1}"; do
    IFS=' ' read -ra tmp <<< "$i"
    # Only Allows partitions, skip if not
    if [ ! "${tmp[5]}" = 'part' ]; then continue; fi
    if [ -z "${tmp[6]}" ]; then
        mntPt+=("-")    # Partition without mountpoint
    else
        mntPt+=("${tmp[6]}")
    fi
    name+=("${tmp[0]}")
    d_size+=("${tmp[3]}")
done

maxInArr "${mntPt[@]}"
maxMntPtLen=$?
maxInArr "${name[@]}"
maxNameLen=$?

options=()

for (( i=0; i < ${#name[@]}; ++i )); do
    # Paddings for entries
    tmp=${#name[i]}
    namePad=$((maxNameLen-tmp+4))
    tmp=${#mntPt[i]}
    mntPtPad=$((maxMntPtLen-tmp+1))

    tmp="$(printf -- "${mntPt[i]} %$mntPtPad.s ${d_size[i]}\n")"
    options+=("${name[i]}")
    options+=("$(printf -- "${name[i]} %$namePad.s ${mntPt[i]} %$mntPtPad.s ${d_size[i]}\n")")
done

calcTermSize
pName="$(whiptail --title "Partitions" --notags --menu "Choose a parition" "${termSize[@]}" 0 -- "${options[@]}" 3>&1 1>&2 2>&3)"
if [ -z $pName ]; then exit; fi  # Terminate on exit

prevInode="/"
nestedDeletedInode=0
while true; do  # Loop until stopped
    entry_name=()
    entry_type=()
    entry_inode=()
    IFS=$'\n' dir=($(sudo fls -a $pName $currentInode))
    for i in "${dir[@]}"; do
        # Folder / File name
        entry_name+=("$(cut -d ':' -f 2- <<< $i | sed -e 's/^[ \t]*//')")

        IFS=' ' read -ra tmp <<< "$(cut -d ':' -f 1 <<< $i)"
        if [ "${tmp[1]}" = "*" ]; then
            entry_type+=("*${tmp[0]}")
            entry_inode+=("${tmp[2]}")
        else
            entry_type+=("${tmp[0]}")
            entry_inode+=("${tmp[1]}")
        fi
    done

    entries=()
    for (( i=0; i < ${#entry_name[@]}; ++i )); do
        tmp=${#entry_type[i]}
        tmp=$((4-tmp))
        entries+=("$i")
        entries+=("$(printf -- "%$tmp.s${entry_type[i]}  ${entry_name[i]}")")
    done
    
    calcTermSize
    tmp="$(whiptail --title "Menu" --notags --cancel-button "Exit" --menu 'Select File/Directory (* - deleted)' "${termSize[@]}" 0 -- "${entries[@]}" 3>&1 1>&2 2>&3)"
    # Exit if exit selected
    if [ -z $tmp ]; then exit; fi
    if [ "${entry_type[tmp]:0-1}" = "d" ]; then  # If entry is directory (ends in d)
        if [ "${entry_type[tmp]:0:1}" = "*" ]; then  # If file deleted (starts with *)
            if [ "${entry_name[tmp]}" = ".." ]; then  # If going back to previous
                nestedDeletedInode=$((nestedDeletedInode-1))
                # Back out of deleted directory completely
                if [ $nestedDeletedInode -eq 0 ]; then  
                    if [ "$prevInode" = "/" ]; then
                        currentInode=""
                    else
                        currentInode="$prevInode"
                    fi
                    continue    # Skip all below
                fi

            else  # Going deeper into deleted directory
                if [ $nestedDeletedInode -eq 0 ]; then  # First deleted level
                    if [ -z "$currentInode" ]; then   # Currently at root
                        prevInode="/"
                    else
                        prevInode="$currentInode"
                    fi
                fi
                nestedDeletedInode=$((nestedDeletedInode+1))
            fi
        fi
        currentInode="${entry_inode[tmp]}"
    elif [ "${entry_type[tmp]:0-1}" = "r" ]; then   # File selected
        if command -v kdialog &> /dev/null; then    # if kdialog exists use
            icatPath=$(kdialog --getexistingdirectory .)
        else    # Defaults to cwd
            icatPath="$PWD/"
        fi
        sudo icat $pName ${entry_inode[tmp]} > "$icatPath${entry_name[tmp]}"
    fi
done



