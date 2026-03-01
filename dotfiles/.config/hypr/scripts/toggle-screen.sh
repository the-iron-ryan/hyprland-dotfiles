#!/bin/bash

# Check current state by reading the monitor.conf file
if grep -q "default-screen-disabled.conf" /home/the-iron-ryan/.mydotfiles/com.ml4w.the-iron-ryan.dotfiles/.config/hypr/conf/monitor.conf; then
    # Currently disabled, enable it
    /home/the-iron-ryan/.mydotfiles/com.ml4w.the-iron-ryan.dotfiles/.config/hypr/scripts/set-screen-disabled.sh false
    echo "Screen enabled"
    notify-send "Laptop Screen Enabled" ""
else
    # Currently enabled, disable it
    /home/the-iron-ryan/.mydotfiles/com.ml4w.the-iron-ryan.dotfiles/.config/hypr/scripts/set-screen-disabled.sh true
    echo "Screen disabled"
    notify-send "Laptop Screen Disabled" ""
fi

hyprctl reload