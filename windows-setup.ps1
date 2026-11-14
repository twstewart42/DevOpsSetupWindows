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
	foreach ($id in 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal') {
		winget list --id $id --exact | Out-Null
		if ($LASTEXITCODE -ne 0) {
			winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
		} else {
			Write-Output "$id already installed"
		}
	}
}

function Install-VscodeExtensions {
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

Write-Output 'Configuring WSL...'
$wslArgs = @($script:GitName, $script:GitEmail) | Where-Object { $_ }
wsl -d $WslDistro bash wsl-setup.sh @wslArgs
