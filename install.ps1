# Web installer for Spac. Run it with:
#   powershell -c "irm https://raw.githubusercontent.com/JohnyLeeJohnes/spac/master/install.ps1 | iex"
# It downloads the app into %LOCALAPPDATA%\Spac, creates the shortcuts and opens it.
#
# Keep this file plain ASCII without a BOM: irm leaves a BOM in the text and iex fails on it,
# and without a BOM Windows PowerShell misreads non-ASCII characters when the file is run from disk.

# The script block keeps the variables out of the session of whoever pasted the command.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $source = 'https://raw.githubusercontent.com/JohnyLeeJohnes/spac/master'
    $target = Join-Path $env:LOCALAPPDATA 'Spac'

    $null = New-Item -ItemType Directory -Force (Join-Path $target 'assets')
    foreach ($file in 'Spac.ps1', 'Spac.xaml', 'assets/spac.ico') {
        Invoke-WebRequest "$source/$file" -OutFile (Join-Path $target $file) -UseBasicParsing
    }

    # A separate process, because the execution policy of this session may not allow script files.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $target 'Spac.ps1') -Install
    if ($LASTEXITCODE) { throw 'Creating the shortcuts failed.' }

    # Started from Win+R this window closes right away, so opening the app is how you see it worked.
    Invoke-Item (Join-Path $target '*.lnk')
}
