rem Add local admin
net user /add {{ node_username }} {{ node_password }}
net localgroup administrators {{ node_username }} /add

rem Rename PS1 files
ren C:\cloud-automation\bootstrap-shim.txt bootstrap-shim.ps1
ren C:\cloud-automation\setup-shim.txt setup-shim.ps1

rem Run the bootstrap shim
powershell -ExecutionPolicy RemoteSigned -File c:\cloud-automation\bootstrap-shim.ps1
