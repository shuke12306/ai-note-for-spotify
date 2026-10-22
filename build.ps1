param([string]$Distribution = 'Ubuntu')
$ErrorActionPreference = 'Stop'

$portableProjectPath = $PSScriptRoot.Replace('\', '/')
$wslProjectPath = & wsl.exe -d $Distribution --exec wslpath -a -u $portableProjectPath
if ($LASTEXITCODE -ne 0) {
    throw 'Could not resolve the project path inside WSL.'
}
$buildScript = $wslProjectPath.Trim() + '/scripts/build.sh'
& wsl.exe -d $Distribution --exec bash $buildScript
if ($LASTEXITCODE -ne 0) {
    throw "Plugin build failed (exit code $LASTEXITCODE)."
}
