<#
.SYNOPSIS
	Install and Setup DevOps Utilities that I routinely need on Windows based development platform
.DESCRIPTION
	Installs git, WSL2, choloately, scoop, python, rancher desktop, VSC
		Win Terminal, and more.
.NOTES
	Intent is to NOT require priviledge escalation/Administrator RunAs  
.EXAMPLE
	PS> ./windows-setup.ps1
#>


$wsl_distro = "Ubuntu-20.04"
$appdata_path = $env:LOCALAPPDATA

## Install Scoop
$has_scoop = (Get-Command scoop) 
if (!$has_scoop) {
	Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
} else {
	Write-Output "Scoop already installed and in path" 
}

# I chose scoop as the default installation method since you can install all these utilities into a user's profile
# without elevated permissions, unlike choloately and other windows installers.
function scoop_install($name, $url, $check, $cow) {
	$has_check = $(Get-Command $check)
	if (!$has_check) {
		scoop install $url -a 64bit
		Write-Output "Installed $name" | cowsay -f $cow
	} else {
		Write-Output "$name already installed and in path" | cowsay -f $cow
	}
}

# Use github API to find latest version of utility and then install exe assets.
function github_latest_install($name, $url, $check, $ext, $cow) {
	$has_check = $(Get-command $check)
	if (!$has_check) {
		Write-Output "Installing $name" | cowsay -f 
		$latest = (Invoke-WebRequest $url | ConvertFrom-Json)
		foreach ($a in $latest.assets) {
			#Write-Output $a.browser_download_url 
			if ($a.browser_download_url -like "*$ext") {
				Write-Output $a.browser_download_url $check
				$webClient = New-Object System.Net.WebClient
				#Add-Content -Path "${name}-installer.${ext}" -Value $webClient.DownloadString($a.browser_download_url)
				#Start-Process -Wait "${name}-installer.${ext}"
			}
		}
	} else {
		write-Output "$name is already installed and in path." | cowsay -f $cow
	}
}

# last resort download method, which is point to direct url and hope for the best
function download_install($name, $url, $check, $cow) {
	$has_check = $(Get-Command $check)
	if (!$has_check) {
		Write-Output "Installing $name"
		$webClient = New-Object System.Net.WebClient
		Add-Content -Path "${name}-installer.exe" -Value $webClient.DownloadString('$url')
		Start-Process -Wait "${name}-installer.exe"
		Write-Output "$name installed" | cowsay -f 
	} else {
		Write-Output "$name is already installed and in path." | cowsay -f $cow
	}
}

# trying very hard to find ways to not lock in versions of these tools since most of them, we just the latest version.		
# Keep in Alphabetical Order please, except Cowsay must be first, since we use it within this script for added flavor
scoop_install cowsay https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/cowsay.json cowsay.ps1 default
scoop_install aws https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/aws.json aws.exe elephant
scoop_install dos2unix https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/dos2unix.json dos2unix.exe tux
# have to reference exact commit for latest dotnet package to avoid updating to 5.X or 6.X unexpectedly
scoop_install dotnet https://raw.githubusercontent.com/ScoopInstaller/Main/cb99ded87a807bd4764f785a407e54174c2d5f82/bucket/dotnet-sdk.json dotnet.exe tux
scoop_install go https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/go.json go.exe cower
scoop_install helm https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/helm.json helm.exe surgery
scoop_install jq https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/jq.json jq.exe stegosaurus
scoop_install kubectl https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/kubectl.json kubectl.exe meow
scoop_install kubectx https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/kubectx.json kubectx.exe skeleton
scoop_install k3sup https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/k3sup.json k3sup.exe beavis.zen
scoop_install packer https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/packer.json packer.exe luke-koala
scoop_install python3 https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/python.json python.exe dragon
scoop_install saml2aws https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/saml2aws.json saml2aws.exe koala
scoop_install starship https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/starship.json starship.exe kiss
scoop_install terraform https://raw.githubusercontent.com/se35710/scoop-main/master/bucket/terraform.json terraform.exe cheese
scoop_install tflint https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/tflint.json tflint.exe moose
scoop_install tfsec https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/tfsec.json tfsec.exe milk
scoop_install vim https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/vim.json vim.exe vader

download_install VSCode 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user' code.cmd moose

github_latest_install rancher-desktop https://api.github.com/repos/rancher-sandbox/rancher-desktop/releases/latest "$appdata_path\Programs\Rancher Desktop\Rancher Desktop.exe" exe small
github_latest_install winget https://api.github.com/repos/microsoft/winget-cli/releases/latest winget.exe msixbundle eyes
github_latest_install winterm https://api.github.com/repos/microsoft/terminal/releases/latest wt.exe msixbundle moofasa

## Install WSL2
function wsl_install() {
	$winver = [System.Environment]::OSVersion.Version.Build
	if ($winver -gt 19041) {
		Write-Output "Supports WSLV2"
		$wsl_answers = $(wsl --status | ConvertFrom-String)
		$wsl_default = ""
		foreach ($w in $wsl_answers.P3) { 
			if ($w -eq "$wsl_distro") {
				$wsl_default = $w
				Write-Output "WSLv2 and $wsl_distro already installed"
			} 
		}
		if ($wsl_distro -ne $wsl_distro) {
			Write-output "Installing WSL and $wsl_distro"
			wsl --install -d $wsl_distro
			wsl --set-default $wsl_distro 2
		}		
	} else {
		Write-Output "Your Windows System is too old, please update and try again."
		Write-Output "WinVer must be 19041 or greater"
	}
	# Set WSL Limits since it can go cray cray and slow the main system down too much
	$wsl_config = [string]::Concat((Get-Item -Path Env:USERPROFILE | get-content),"\.wslconfig")
	#$wsl_config = "wslconfig" #local testing
	$has_wsl_config = (Get-ChildItem $wsl_config -ErrorAction Ignore)
	$wsl_content = "[wsl2]
memory=4GB
processors=2" #keep the spacing/tabs as is please
	if (!$has_wsl_config) {
		Write-Output "Create WSL Config"
		Set-Content -Path $wsl_config -Value ""
		if (!( get-content $wsl_config | select-string memory=4GB)) {
			Set-Content -Path $wsl_config -Value $wsl_content
			wsl --shutdown
		}
	}
}

wsl_install

# install recommended VSCode extensions
function vscode_extension_install() {
	Write-Output "VSCode plugin"
	$extensions = (Get-Content ".vscode/extensions.json"| ConvertFrom-Json)
	$installed = (code --list-extensions)
	foreach ( $e in $extensions.recommendations ) {
		if ($e -notIn $installed) {
			Write-Output "Install $e plugin to VSCode"
			code install --install-extension $d 
		} else {
			Write-Output "$e VSCode plugin already installed"
		}
	}
}
vscode_extension_install

# git configuration
if ((git config --get user.name) -eq $null) {
	$git_username = Read-Host -Prompt 'Input your git user.name: '
	git config --global user.name $git_username
}
if ((git config --get user.email) -eq $null) {
	$git_email = Read-Host -Prompt 'Input your git user.email: '
	git config --global user.email $git_email
}


# use Bash script to configure setting inside Linux/WSL
Write-Output "Configuring WSL..."
Start-Sleep -s 5
dos2unix wsl-setup-sudo.sh
dos2unix wsl-setup.sh
wsl -d $wsl_distro -u root bash wsl-setup-sudo.sh $git_username $git_email
wsl -d $wsl_distro bash wsl-setup.sh $git_username $git_email
Write-Output ""

