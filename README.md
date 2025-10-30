# system-init
Universal shell scripts to install minimal prerequisites on various platforms

Linux
```sh
curl https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.sh | sh
```

Windows
Powershell
```sh
iex (iwr "https://raw.githubusercontent.com/yuxiaoli/system-init/refs/heads/main/init.bat" -UseBasicParsing).Content
```
```sh
(iwr "https://raw.githubusercontent.com/yuxiaoli/system-init/main/init.ps1" -UseBasicParsing).Content > init.ps1; .\init.ps1 -Yes
```

CMD
```sh
init.bat --yes

init.bat --no-update
```
