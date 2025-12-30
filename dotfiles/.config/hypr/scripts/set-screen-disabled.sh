
#!/bin/bash

# Accept disabled flag as first argument (true/false)
disabled=${1:-false}

if [ "$disabled" = "true" ]; then
    echo "source = ~/.config/hypr/conf/monitors/default-screen-disabled.conf" >~/.config/hypr/conf/monitor.conf
    echo "source = ~/.config/hypr/conf/workspaces/default-screen-disabled.conf" >~/.config/hypr/conf/workspace.conf
else
    echo "source = ~/.config/hypr/conf/monitors/default.conf" >~/.config/hypr/conf/monitor.conf
    echo "source = ~/.config/hypr/conf/workspaces/default.conf" >~/.config/hypr/conf/workspace.conf
fi