<#
.SYNOPSIS
	Bootstrap WSL2 + GUI apps on Windows, then configure tooling inside WSL.
.DESCRIPTION
	DevOps CLIs live only in WSL (see config/mise.toml). This script installs
	WSL (Ubuntu 24.04), VS Code, Windows Terminal, recommended VS Code
	extensions, and runs wsl-setup.sh.
.NOTES
	Run from the repo root in a user-level PowerShell. Prerequisite: Git for Windows.
.EXAMPLE
	PS> .\windows-setup.ps1
#>
$ErrorActionPreference = 'Stop'
$WslDistro = 'Ubuntu-24.04'

function Install-Wsl {
	if ([System.Environment]::OSVersion.Version.Build -lt 19041) {
		throw 'Windows build 19041 or newer is required for WSL2. Please update and retry.'
	}
	$installed = (wsl -l -q) -replace "`0", '' | ForEach-Object { $_.Trim() }
	if ($installed -notcontains $WslDistro) {
		Write-Output "Installing WSL and $WslDistro"
		wsl --install -d $WslDistro
		wsl --set-default $WslDistro
		# A fresh distro needs a reboot and/or first launch to create the Linux user
		# before wsl-setup.sh can run, so stop here.
		$script:WslJustInstalled = $true
	} else {
		Write-Output "$WslDistro already installed"
	}
	# Limit WSL resources so it can't starve the host
	$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
	if (!(Test-Path $wslConfig)) {
		Set-Content -Path $wslConfig -Value "[wsl2]`nmemory=4GB`nprocessors=2"
		wsl --shutdown
	}
}

function Install-GuiApps {
	foreach ($id in 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal', 'RedHat.Podman', 'RedHat.Podman-Desktop') {
		winget list --id $id --exact | Out-Null
		if ($LASTEXITCODE -ne 0) {
			winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
		} else {
			Write-Output "$id already installed"
		}
	}
	# Pick up PATH changes (e.g. `code`) from installs made in this session
	$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
		[Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-VscodeExtensions {
	if (!(Get-Command code -ErrorAction SilentlyContinue)) {
		Write-Warning 'VS Code (code) not on PATH yet; open a new terminal and re-run to install extensions.'
		return
	}
	$recommended = (Get-Content '.vscode/extensions.json' | ConvertFrom-Json).recommendations
	$installed = code --list-extensions
	foreach ($e in $recommended) {
		if ($e -notin $installed) {
			code --install-extension $e
		} else {
			Write-Output "$e VSCode extension already installed"
		}
	}
}

# Create and start the Podman machine that Podman Desktop and WSL share.
# Rootful matches Podman Desktop's default; wsl-setup.sh connects Ubuntu to it.
function Start-PodmanMachine {
	if (!(Get-Command podman -ErrorAction SilentlyContinue)) {
		Write-Warning 'podman not on PATH yet; open a new terminal and re-run to set up the Podman machine.'
		return
	}
	$machines = podman machine list --format '{{.Name}}'
	if ($machines -notcontains 'podman-machine-default') {
		Write-Output 'Creating Podman machine (podman-machine-default, rootful)'
		podman machine init --rootful
	}
	if ((podman machine inspect --format '{{.State}}' podman-machine-default) -ne 'running') {
		podman machine start podman-machine-default
	}
}

function Set-GitIdentity {
	$script:GitName = git config --get user.name
	$script:GitEmail = git config --get user.email
	if (!$script:GitName) {
		$script:GitName = Read-Host -Prompt 'Input your git user.name'
		git config --global user.name $script:GitName
	}
	if (!$script:GitEmail) {
		$script:GitEmail = Read-Host -Prompt 'Input your git user.email'
		git config --global user.email $script:GitEmail
	}
}

Install-Wsl
Install-GuiApps
Install-VscodeExtensions
Set-GitIdentity

if ($script:WslJustInstalled) {
	Write-Output "WSL and $WslDistro were just installed. Reboot if prompted, launch '$WslDistro' once"
	Write-Output 'to create your Linux user, then re-run .\windows-setup.ps1 to finish setup.'
	exit 0
}

Start-PodmanMachine

Write-Output 'Configuring WSL...'
$wslArgs = @($script:GitName, $script:GitEmail) | Where-Object { $_ }
# --exec skips the Linux shell so arguments with spaces (e.g. "First Last") stay intact
wsl -d $WslDistro --exec bash wsl-setup.sh @wslArgs
