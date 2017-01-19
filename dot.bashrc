# remap CAPS_LOCK to CTRL
perl -E 'if(`which setxkbmap`){ `setxkbmap -option \"caps:ctrl_modifier\"`}'
