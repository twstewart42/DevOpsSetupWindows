# Plain PowerShell tests for helpers in windows-setup.ps1 (runs on pwsh, any OS).
# Run: pwsh -NoProfile -File tests/windows-setup.tests.ps1
$ErrorActionPreference = 'Stop'
$script:Fails = 0
function Check($name, [scriptblock]$cond) {
	if (& $cond) { "PASS $name" } else { "FAIL $name"; $script:Fails++ }
}

. (Join-Path $PSScriptRoot '..' 'windows-setup.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
	# Copy-MiseConfig: new dest is created (with parent dirs)
	$src = Join-Path $tmp 'src.toml'; Set-Content $src 'v1'
	$dest = Join-Path $tmp 'a/b/config.toml'
	Copy-MiseConfig $src $dest
	Check 'copy creates dest'              { (Get-Content $dest) -eq 'v1' }
	# differing user file is backed up once; identical rerun does not touch backup
	Set-Content $dest 'mine'
	Copy-MiseConfig $src $dest
	Check 'copy backs up differing file'   { (Get-Content "$dest.bak") -eq 'mine' -and (Get-Content $dest) -eq 'v1' }
	Copy-MiseConfig $src $dest
	Check 'rerun keeps backup'             { (Get-Content "$dest.bak") -eq 'mine' }
	Set-Content $src 'v2'; Copy-MiseConfig $src $dest
	Check 'rerun picks up repo edits'      { (Get-Content $dest) -eq 'v2' -and (Get-Content "$dest.bak") -eq 'mine' }

	# Add-PathEntry: pure string function
	Check 'adds entry to path'             { (Add-PathEntry 'C:\a;C:\b' 'C:\shims') -eq 'C:\a;C:\b;C:\shims' }
	Check 'no duplicate entry'             { (Add-PathEntry 'C:\a;C:\shims' 'C:\shims') -eq 'C:\a;C:\shims' }
	Check 'case/trailing slash insensitive' { (Add-PathEntry 'C:\a;c:\SHIMS\' 'C:\shims') -eq 'C:\a;c:\SHIMS\' }
	Check 'empty path'                     { (Add-PathEntry '' 'C:\shims') -eq 'C:\shims' }
} finally {
	Remove-Item -Recurse -Force $tmp
}
exit $script:Fails
