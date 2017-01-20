# profile



# vim will use custom config in $MYVIMRC
export MYVIMRC=~/.vimrc

#NOTE: i set colorscheme in .vimrc to ir_black then use Grey On Black built-in scheme with Solarized palette in Gnome Terminnal (Terminal->Preferences->Profiles->Edit->Color)

# add ~/local/bin to PATH
export PATH=~/local/bin:$PATH

# set locale to UTF-8
export LC_ALL="en_US.UTF-8"

# CTRL-P will switch me into ~/dpp dir
bind '"\C-p":"cd ~/dpp && pwd\n"';

# remap CAPS_LOCK to CTRL on linux
perl -E 'if(`which setxkbmap`){ `setxkbmap -option \"caps:ctrl_modifier\"`}'

# + also remap CAPS_LOCK to ESC on linux (usefull in vim)
perl -E 'if(`which xcape`){ `xcape -e \"Caps_Lock=Escape\"`}'

# set vi mode on command line
set -o vi
