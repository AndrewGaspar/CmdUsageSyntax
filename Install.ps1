$moduleDirectory = "~\Documents\WindowsPowerShell\Modules"

mkdir $moduleDirectory -ErrorAction SilentlyContinue

$existing = Get-Module "$moduleDirectory\CmdUsageSyntax" -ListAvailable

if($existing) {
    $local = Get-Module .\CmdUsageSyntax -ListAvailable
    if($local.Version -lt $existing.Version) {
        Write-Error "Module is already installed"
        return
    } else {
        rmdir -Recurse -Force "$moduleDirectory\CmdUsageSyntax"
    }
}

Copy-Item -Recurse $PSScriptRoot\CmdUsageSyntax $moduleDirectory