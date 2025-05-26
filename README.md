# Cloudbase-Init for Win 11 Client
Instructions and config for running Cloudbase-Init on a Windows 11 client via Proxmox PVE8.4.1

## Prepare a Win11 Image 
1. Install Win11 VM and edit the security policy to allow RDP without a password: `Run>gpedit.msc`. Then `Computer Configuration>Windows Settings>Security Settings>Local Policies>Security Options` and disable `‘Accounts: Limit local account use of blank passwords to console only’ `
2. Download cloudbase-init installer from online.
3. Download and install VirtIO paravirtualised driver from Proxmox online.
4. Activate the default Administrator account with `net user Administrator /active:yes`
5. Then transfer into this account and delete the others with:
```
net user <OldAdmin> /delete
rmdir /s /q "C:\Users\johndoe"
```

## Prepare Cloudbase Install
1. Install Cloudbase-init, to run as LocalSystem, but do not run the sys prep yet. Ensure Cloudbase-init was installed to run as LocalSystem
2. For a Win11 client (i.e. not a server), add these lines to the `Unattend.xml` (from [https://pve.proxmox.com/wiki/Cloud-Init_Support]) to enable the default Administrator account (because by default, sysprep will disable the default Administrator account):
```
<RunSynchronousCommand wcm:action="add">
  <Path>net user administrator /active:yes</Path>
  <Order>1</Order>
  <Description>Enable Administrator User</Description>
</RunSynchronousCommand>
```
  * _NB: Ensure the ‘order’ of subsequent items in Unattend.xml on are incremented to allow this command to execute first_
3. Then copy the necessary config files for `cloudbase-init.json` and `cloudbase-init-unattend.json` into the conf folder.

## Configure Cloudbase and Win11 to run with Sysprepped image
1. Sysprep has issues (especially in the standard Win11 client) with certain apps not being installed for all users. We can fix this removing them en-mass. Just before sys prep: (it won’t boot properly afterwards without sysprep, and you can't open files after running these commands)
```
Get-AppxPackage -AllUsers | Remove-AppxPackage
Get-AppxProvisionedPackage -Online | Remove-AppxProvisionedPackage -Online
```
  * _If this fails, go into the log file to see the error and remove that app(log can be found at C:\Windows\System32\Sysprep\Panther\setupact.log)_
2. Convert to a console (ie. **do not** use RDP for the next step), and then select sysprep to run without rebooting (or use powershell below if tick box is already closed). _Once sys prep has completed, you won’t be able to open any notepad apps._
```
cd 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf'
C:\Windows\System32\sysprep\sysprep.exe /generalize /oobe /unattend:Unattend.xml /quit
```
3. By default, sysprep disables the Administrator account and disables any non-default services so run in cmd:
```
net users Administrator /active:yes
sc config cloudbase-init start= auto
``` 
4. Shutdown the image, cloning, snapshotting or creating a template as desired

## Enabling Username injection in Proxmox (patching our Proxmox instance)
1. In Proxmox PVE 8.4.1 the configdrive2 does not generate a `admin_username` key in `meta_data.json`. The Cloudbase plugin service that pulls injected metadata using service `baseopenstackservice.py` (found in `C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Lib\site-packages\cloudbaseinit\metadata\services`)  expects to find the field ‘admin_username’ in a dictionary called `meta`
  1. This is found in the function `get_admin_username(self)`
3. We can apply a patch to Proxmox PVE that will generate a `meta` field  in `configudrive2/meta_data.json` by inserting the following lines into cloudbase_configdrive2_metadata in Cloudinit.pm. The following lines should be entered at the bottom of the `sub cloudbase_configdrive2_metadata` in `Cloudinit.pm` (which can be found in `/usr/share/perl5/PVE/QemuServer/`)
```
--- Cloudinit.pm    	2025-05-19 18:26:06
+++ Cloudinit.pm.patched	2025-05-23 22:25:48
@@ -333,6 +333,17 @@
 	    $i++;
 	}
     }
+
+#PATCH inserted here to create new 'meta' dict
+    my ($hostname, undef) = get_hostname_fqdn($conf, $uuid);
+    $meta_data->{'meta'} = {
+        hostname => $hostname,
+        uuid => $uuid,
+        admin_username => $conf->{ciuser} || 'NewAdmin',
+        admin_pass => $conf->{cipassword} || '',
+    };
+
+
     my $json = encode_json($meta_data);
     return $json;
 }
```

## Enabling SSH Key Injection on Windows (installing OpenSSH Server)
1. First ensure the Windows image is correct by running `dism.exe /Online /Cleanup-image /Restorehealth && sfc /scannow`
2. In Settings go _System > Optional features > View features > OpenSSH_ and install the server version
  1. You can also try `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`
3. Once installed, check the install with `Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'`
4. We next need to override a setting in the config (_C:\ProgramData\ssh\sshd_config_) that specifies OpenSSH to look for ‘Administrator’ group keys in a separate location by commenting out:
```
#Match Group administrators
#       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```
  1. _NB: Open Notepad.exe as an Administrator first_
5. Finally, we need to set the sshd service to start automatically `sc config sshd start= auto && sc start sshd`

