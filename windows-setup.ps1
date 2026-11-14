<#
.SYNOPSIS
	Set up DevOps tooling on Windows and in WSL2 from one mise config.
.DESCRIPTION
	Installs the DevOps CLIs from config/mise.toml natively with mise, plus WSL
	(Ubuntu 24.04), VS Code, Windows Terminal, Podman + Podman Desktop and
	recommended VS Code extensions, then runs wsl-setup.sh inside WSL.
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

function Install-WingetPackages {
	# Amazon.AWSCLI: mise's awscli has no Windows build (AWS ships an MSI), see config/mise.toml
	$ids = 'jdx.mise', 'Amazon.AWSCLI', 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal',
		'RedHat.Podman', 'RedHat.Podman-Desktop'
	foreach ($id in $ids) {
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

# Copy-MiseConfig <src> <dest>: copy the repo config over dest, backing up a
# differing user file once. (Copy, not symlink: symlinks need admin/dev mode.)
function Copy-MiseConfig([string]$Src, [string]$Dest) {
	New-Item -ItemType Directory -Force (Split-Path $Dest) | Out-Null
	if ((Test-Path $Dest) -and !(Test-Path "$Dest.bak") -and
		(Get-FileHash $Src).Hash -ne (Get-FileHash $Dest).Hash) {
		Move-Item $Dest "$Dest.bak"
	}
	Copy-Item $Src $Dest -Force
}

# Add-PathEntry <path> <entry>: return the ;-separated path with entry appended
# unless already present (case and trailing-slash insensitive).
function Add-PathEntry([string]$Path, [string]$Entry) {
	$parts = @($Path -split ';' | Where-Object { $_ })
	$norm = { param($p) $p.TrimEnd('\').ToLowerInvariant() }
	if ($parts | Where-Object { (& $norm $_) -eq (& $norm $Entry) }) { return $Path }
	return (@($parts) + $Entry) -join ';'
}

# Install the same tools as WSL, natively, and put mise's shims on the user PATH
# so they work in PowerShell, cmd and VS Code.
function Install-MiseTools {
	if (!(Get-Command mise -ErrorAction SilentlyContinue)) {
		Write-Warning 'mise not on PATH yet; open a new terminal and re-run to install the DevOps tools.'
		return
	}
	Copy-MiseConfig (Join-Path $PSScriptRoot 'config\mise.toml') (Join-Path $HOME '.config\mise\config.toml')
	mise install --yes
	$shims = Join-Path $env:LOCALAPPDATA 'mise\shims'
	$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
	$newPath = Add-PathEntry $userPath $shims
	if ($newPath -ne $userPath) {
		[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
		$env:Path = Add-PathEntry $env:Path $shims
	}
	mise exec -- az extension show --name azure-devops 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0) {
		mise exec -- az extension add --name azure-devops --only-show-errors
	}
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

function Invoke-Main {
	Install-Wsl
	Install-WingetPackages
	Install-MiseTools
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
}

# Dot-sourcing (tests) loads the functions without running setup
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
