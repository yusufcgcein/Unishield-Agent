#!/bin/sh

## Unishield 360 Metric Agent / Wazuh agent uninstaller
## Stop and remove application
sudo /Library/Ossec/bin/wazuh-control stop
sudo /bin/rm -r /Library/Ossec*

# remove launchdaemons
/bin/rm -f /Library/LaunchDaemons/com.wazuh.agent.plist

## remove StartupItems
/bin/rm -rf /Library/StartupItems/WAZUH

## Remove User and Groups
/usr/bin/dscl . -delete "/Users/wazuh"
/usr/bin/dscl . -delete "/Groups/wazuh"

/usr/sbin/pkgutil --forget com.unishield360.pkg.wazuh-agent
/usr/sbin/pkgutil --forget com.unishield360.pkg.wazuh-agent-etc

# In case it was installed via Puppet pkgdmg provider
if [ -e /var/db/.puppet_pkgdmg_installed_wazuh-agent ]; then
    rm -f /var/db/.puppet_pkgdmg_installed_wazuh-agent
fi

echo
echo "Unishield 360 agent correctly removed from the system."
echo

exit 0