# system-init
Universal shell scripts to install minimal prerequisites on various platforms

Linux
```sh
curl https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.sh | sh
```
Use sudo
```sh
curl -sS https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.sh | sudo -E sh
```
`-E/--preserve-env`: Preserve current environment variables

Windows
Powershell
```powershell
iex (iwr "https://raw.githubusercontent.com/yuxiaoli/system-init/refs/heads/main/init.bat" -UseBasicParsing).Content
```
```powershell
(iwr "https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.ps1" -UseBasicParsing).Content > init.ps1; .\init.ps1 -Yes -NoUpdate
```
Run as administrator
```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command','(iwr "https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.ps1" -UseBasicParsing).Content > init.ps1; & .\init.ps1 -Yes -NoUpdate'
```

CMD
```sh
init.bat --yes

init.bat --no-update
```
