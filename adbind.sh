#!/bin/sh
clear

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
echo "This script must be run as root" 1>&2
exit 1
fi

#choosing a domain to bind to
echo 'Please choose your domain (type corresponding number, and hit enter): \n1) NORTHAMERICA \n2) EUROPE \n3) REDMOND \n4) SOUTHPACIFIC \n5) Other'
read n
case $n in
1) fqdomain="contoso1.com";;
2) fqdomain="contoso2.com";;
3) fqdomain="contoso3.com";;
4) fqdomain="contoso4.com";;
5) echo "Please contact IT, we'll need to complete this operation manually" | exit 5;;
*) invalid option;;
esac

#getting domain from fqdm
domain=`echo ${fqdomain} | cut -f1 -d "."`

# AD Bind parameters
computerid=`/usr/sbin/scutil --get LocalHostName`
udn="userid"               # username of a privileged network user
password="password"                         # password of a privileged network user
ou="CN=Computers,DC=${domain},DC=contoso,DC=com"          # Distinguished name of container for the computer

check4AD=`/usr/bin/dscl localhost -list . | grep "Active Directory"`

# If the machine is bound to AD already, we can skip the binding process
if [ "${check4AD}" != "Active Directory" ]; then

# Activate the AD plugin

defaults write /Library/Preferences/DirectoryService/DirectoryService "Active Directory" "Active"
plutil -convert xml1 /Library/Preferences/DirectoryService/DirectoryService.plist
echo "Binding to Active Directory"

#Replaced 5 second required sleep with a progress bar
for i in {001..65}; do
printf '#' .;sleep 0.1;
done

# Bind to AD
dsconfigad -f -a $computerid -domain $fqdomain -u $udn -p "$password" -ou "$ou"
fi


# Check for AD bound once more
check4AD=`/usr/bin/dscl localhost -list . | grep "Active Directory"`

# If the machine is not bound to AD, then there's no purpose going any further.
if [ "${check4AD}" != "Active Directory" ]; then
echo -e 'There was an issue binding to Active Directory.\nPlease verify you are plugged into the network. '; exit 1
fi

printf "\nWelcome to CorpNet"

#When prompted, ONLY include ID, do not include domain or domain\username. Only the username
netIDprompt="Please enter the AD account, username only, for this user: "
netPWprompt="Please enter the Password to this AD account: "
compPWprompt="Please enter your computer password: "
listUsers="$(/usr/bin/dscl . list /Users | grep -v _ | grep -v root | grep -v uucp | grep -v amavisd | grep -v nobody | grep -v messagebus | grep -v daemon | grep -v www | grep -v Guest | grep -v xgrid | grep -v windowserver | grep -v unknown | grep -v unknown | grep -v tokend | grep -v sshd | grep -v securityagent | grep -v mailman | grep -v mysql | grep -v postfix | grep -v qtss | grep -v jabber | grep -v cyrusimap | grep -v clamav | grep -v appserver | grep -v appowner) FINISHED"
#listUsers="$(/usr/bin/dscl . list /Users | grep -v -e _ -e root -e uucp -e nobody -e messagebus -e daemon -e www -v Guest -e xgrid -e windowserver -e unknown -e tokend -e sshd -e securityagent -e mailman -e mysql -e postfix -e qtss -e jabber -e cyrusimap -e clamav -e appserver -e appowner) FINISHED"
FullScriptName=`basename "$0"`
ShowVersion="$FullScriptName $Version"
osvers=$(sw_vers -productVersion | awk -F. '{print $2}')
lookupAccount=helpdesk
OS=`/usr/bin/sw_vers | grep ProductVersion | cut -c 17-20`

RunAsRoot()
{
##  Pass in the full path to the executable as $1
if [[ "${USER}" != "root" ]] ; then
echo
echo "***  This application must be run as root.  Please authenticate below.  ***"
echo
sudo "${1}" && exit 0
fi
}

RunAsRoot "${0}"

until [ "$user" == "FINISHED" ]; do

printf "%b" "\a\n\nSelect a user to convert or select FINISHED:\n" >&2

select user in $listUsers; do

if [ "$user" = "FINISHED" ]; then
echo "Thanks for using!"
break
elif [ -n "$user" ]; then
if [ `who | grep console | awk '{print $1}'` == "$user" ]; then
echo "This user is logged in.\nPlease log this user out and log in as another admin"
exit 1
fi


#Local computer password goes here
printf "\e[1m$compPWprompt"
read -s comppw
printf "\n"

# Verify NetID
printf "\e[1m$netIDprompt"
#user ID goes here
read netname

#user PW goes here
printf "\e[1m$netPWprompt"
read -s netpw

# input USR/PW value to plist for later FileVault use
if [ -e /users/shared/FV.plist ]; then
	/usr/libexec/PlistBuddy -c "set AdditionalUsers:0:Username $netname" /users/shared/FV.plist
	/usr/libexec/PlistBuddy -c "set AdditionalUsers:0:Password $netpw" /users/shared/FV.plist
else
	echo"\nPlease confirm that FV.plist is located in the Users Shared directory before continuing."
	exit 1
fi


# Determine location of the users home folder
userHome=`/usr/bin/dscl . read /Users/$user NFSHomeDirectory | cut -c 19-`

# Get list of groups
echo "\nChecking group memberships for local user $user"
lgroups="$(/usr/bin/id -Gn $user)"
#long loading bit


if [[ $? -eq 0 ]] && [[ -n "$(/usr/bin/dscl . -search /Groups GroupMembership "$user")" ]]; then

# Delete user from each group it is a member of
for lg in $lgroups;
do
/usr/bin/dscl . -delete /Groups/${lg} GroupMembership $user >&/dev/null
done
fi

# Delete the primary group
if [[ -n "$(/usr/bin/dscl . -search /Groups name "$user")" ]]; then
/usr/sbin/dseditgroup -o delete "$user"
fi

# Get the users guid and set it as a var
guid="$(/usr/bin/dscl . -read "/Users/$user" GeneratedUID | /usr/bin/awk '{print $NF;}')"
if [[ -f "/private/var/db/shadow/hash/$guid" ]]; then
/bin/rm -f /private/var/db/shadow/hash/$guid
fi

# Rename home directory to OLD_Username
/bin/mv $userHome /Users/old_$user

# Refresh Directory Services
if [[ ${osvers} -ge 7 ]]; then
/usr/bin/killall opendirectoryd
else
/usr/bin/killall DirectoryService
fi
sleep 20
/usr/bin/id $netname

# Check if there's a home folder there already, if there is, exit before we wipe it
if [ -f /Users/$netname ]; then
echo "Oops, theres a home folder there already for $netname.\nIf you don't want that one, delete it in the Finder first,\nthen run this script again."
exit 1
else

/bin/mv /Users/old_$user /Users/$netname
echo "Home for $netname now located at /Users/$netname"

#Find files owned by the old username and re-associate with new username
find /Users/$netname -user $user -exec chown $netname {} \;
sleep 3

#Delete user
/usr/bin/dscl . -delete "/Users/$user"

# Set Symbolic Link to old account (to maintain links for various applications)
cd /Users
ln -s /Users/$netname $user
echo "Symbolic link to /Users/$user has been set"

/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n $netname

echo "Account for $netname has been created on this computer"

echo "Assigning admin rights..."
/usr/sbin/dseditgroup -o edit -a "$netname" -t user admin; echo "Admin rights assigned";

echo "Assigning FileVault permissions to $netname"
fdesetup add -inputplist < /users/shared/FV.plist

echo "Setting & Syncing new keychain password"
security set-keychain-password -o $comppw -p $netpw /Users/$user/Library/Keychains/login.keychain
defaults write com.apple.keychainaccess SyncLoginPassword -bool true

#delete plist files which contained creds
sleep 5
rm -f /users/shared/FV.plist

#Office Compatibility block - clears out cached settings that cause EXC_BAD_ACCESS errors
if [ -x /Applications/Microsoft\ Lync.app ]; then

	rm -f /Users/$netname/Library/Preferences/com.microsoft.Lync.plist
    rm -f /Users/$netname/Library/Preferences/ByHost/com.microsoft.Lync.plist
	rm -f /Users/$netname/Library/Preferences/ByHost/MicrosoftLync*
	rm -f /Users/$netname/Library/Caches/com.microsoft.Lync
    rm -r /Library/Caches/com.microsoft.Lync
	rm -r /Users/$netname/Library/Internet\ Plug-Ins/MeetingJoinPlugin.plugin
    rm -r /Library/Internet\ Plug-Ins/MeetingJoinPlugin.plugin
	rm -f /Users/$netname/Library/Logs/Microsoft-Lync*
	rm -f /Users/$netname/Library/Logs/Microsoft-Lync.log
	rm -r /Users/$netname/Documents/Microsoft\ User\ Data/Microsoft\ Lync\ Data
	rm -r /Users/$netname/Documents/Microsoft\ User\ Data/Microsoft\ Lync\ History
    security delete-internet-password -s "msoCredentialSchemeADAL"

fi

#removes OneNote keychain item that causes corruption post-account migration
if [ -x /Applications/Microsoft\ OneNote.app ]; then

    security delete-internet-password -s "msoCredentialSchemeADAL"

fi

#file permission block - changing any file permissions tied to previous username and reset them to new username

echo "Analyzing remaining file/folder permissions"
diskutil repairPermissions /

echo "Migration Complete!"

fi

break
else
echo "Invalid selection!"
fi
done
done
