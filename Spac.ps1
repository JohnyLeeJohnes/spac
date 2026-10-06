# Spáč: naplánuje vypnutí počítače přes shutdown.exe. Okno je popsané ve Spac.xaml.
#   Spac.ps1             spustí aplikaci
#   Spac.ps1 -Install    vytvoří zástupce s ikonou v nabídce Start, na ploše a ve složce se Spáčem
param([switch]$Install)

$ErrorActionPreference = 'Stop'
$icon = Join-Path $PSScriptRoot 'assets\spac.ico'

if ($Install) {
    $shell = New-Object -ComObject WScript.Shell
    # Nabídka Start, plocha a složka se Spáčem (ať je i tam na co kliknout).
    foreach ($directory in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('DesktopDirectory'), $PSScriptRoot) {
        # WScript.Shell ukládá texty v kódové stránce systému a "č" v ní být nemusí.
        # Proto se zástupce uloží jako Spac.lnk a přejmenuje až potom, a popisek se "č" vyhýbá.
        $plain = Join-Path $directory 'Spac.lnk'
        $link = $shell.CreateShortcut($plain)
        # conhost --headless spustí PowerShell bez okna konzole.
        $link.TargetPath = "$env:SystemRoot\System32\conhost.exe"
        $link.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $link.WorkingDirectory = $PSScriptRoot
        $link.IconLocation = $icon
        $link.Description = 'Vypne PC, až usneš'
        $link.Save()
        if ($shell.CreateShortcut($plain).Arguments -ne $link.Arguments) {
            Remove-Item $plain
            throw "Cesta $PSScriptRoot obsahuje znaky, které zástupce neunese. Přesuň složku jinam a zkus to znovu."
        }
        Move-Item $plain (Join-Path $directory 'Spáč.lnk') -Force
    }
    'Hotovo. Zástupce Spáč je v nabídce Start, na ploše a v téhle složce.'
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Microsoft.VisualBasic

# Dvě volání Windows API. Když se Add-Type nepovede (třeba kvůli zásadám počítače), Spáč běží dál,
# jen má světlý titulek a nepozná, že je hibernace vypnutá.
$native = $null
try {
    $native = Add-Type -Namespace Spac -Name Native -PassThru -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
[DllImport("powrprof.dll")] [return: MarshalAs(UnmanagedType.U1)]
public static extern bool IsPwrHibernateAllowed();
'@
} catch { }

# Návratové kódy shutdown.exe
$nothingScheduled = 1116
$alreadyScheduled = 1190

$statePath = Join-Path $env:LOCALAPPDATA 'Spac\pending'
$limit = @{ HoursBox = 23; MinutesBox = 59 }
$words = @{
    Shutdown  = @{ Accusative = 'vypnutí'; Sentence = 'Počítač se vypne' }
    Restart   = @{ Accusative = 'restart'; Sentence = 'Počítač se restartuje' }
    Hibernate = @{ Accusative = 'hibernaci'; Sentence = 'Počítač přejde do hibernace' }
    LogOff    = @{ Accusative = 'odhlášení'; Sentence = 'Odhlášení proběhne' }
}

# Force, Hybrid a Restore je to, co si uživatel naklikal; zobrazený stav přepínačů se z toho
# odvozuje podle zvolené akce. Countdown = @{ Action; Seconds; Arguments; Due (UTC) }.
$state = @{
    Force = $false; Hybrid = $false; Restore = $false
    Countdown = $null
    Notice = $null; NoticeIsError = $false
    Rendering = $false
}

# ---- shutdown.exe ----

# /h a /l přepínač /t neznají, takže u nich odpočítává Spáč sám.
function Test-TimedByWindows($action) { $action -in 'Shutdown', 'Restart' }

function Invoke-Shutdown([string]$arguments) {
    # Chybovou hlášku píše shutdown.exe na stderr; s 'Stop' by z ní byla výjimka.
    $ErrorActionPreference = 'Continue'
    $output = & "$env:SystemRoot\System32\shutdown.exe" $arguments.Split(' ') 2>&1 | ForEach-Object { "$_" }
    @{ Code = $LASTEXITCODE; Message = ($output -join "`n").Trim() }
}

# ---- Uložený odpočet ----
# U akcí časovaných Windows se odpočet ukládá na disk, aby šel po znovuotevření Spáče zrušit.

function Save-Countdown($countdown) {
    try {
        $null = New-Item -ItemType Directory -Force (Split-Path $statePath)
        $fields = $countdown.Due.Ticks, $countdown.Action, $countdown.Seconds, $countdown.Arguments
        [IO.File]::WriteAllText($statePath, $fields -join '|')
    } catch { }   # Bez souboru jen odpočet nepřežije zavření okna.
}

function Read-Countdown {
    try {
        $parts = [IO.File]::ReadAllText($statePath) -split '\|', 4
        $countdown = @{
            Due = [DateTime]::new([long]$parts[0], 'Utc')
            Action = $parts[1]
            Seconds = [int]$parts[2]
            Arguments = $parts[3]
        }
        # Ukládají se jen odpočty Windows; nic jiného ze souboru nespouštíme.
        if ((Test-TimedByWindows $countdown.Action) -and $countdown.Seconds -gt 0 -and $countdown.Due -gt [DateTime]::UtcNow) {
            return $countdown
        }
    } catch { }   # Chybějící nebo poškozený soubor = žádný odpočet.
    Clear-Countdown
}

function Clear-Countdown {
    try { [IO.File]::Delete($statePath) } catch { }
}

# ---- Čtení formuláře ----

function Get-Action {
    foreach ($action in 'Restart', 'Hibernate', 'LogOff') {
        if ($ui["${action}Tile"].IsChecked) { return $action }
    }
    'Shutdown'
}

function Read-Box($box) {
    $value = 0
    if ([int]::TryParse($box.Text, [ref]$value)) { [Math]::Min($value, $limit[$box.Name]) } else { 0 }
}

function Write-Box($box, $value) {
    $box.Text = $value.ToString($(if ($box.Name -eq 'HoursBox') { '0' } else { '00' }))
}

function Step-Box($box, $delta) {
    Write-Box $box ([Math]::Max(0, [Math]::Min($limit[$box.Name], (Read-Box $box) + $delta)))
    $box.SelectAll()
}

function Get-Minutes { (Read-Box $ui.HoursBox) * 60 + (Read-Box $ui.MinutesBox) }

function Get-Arguments {
    $action = Get-Action
    $timed = Test-TimedByWindows $action
    $flags = @(switch ($action) {
        # /sg a /hybrid se navzájem vylučují, shutdown.exe tu kombinaci odmítne.
        'Shutdown' { if ($state.Restore) { '/sg' } else { '/s'; if ($state.Hybrid) { '/hybrid' } } }
        'Restart' { if ($state.Restore) { '/g' } else { '/r' } }
        'Hibernate' { '/h' }
        'LogOff' { '/l' }
    })
    # S odpočtem zavírají Windows aplikace natvrdo vždy, proto je u /t i /f.
    if ($state.Force -or $timed) { $flags += '/f' }
    if ($timed) { $flags += "/t $((Get-Minutes) * 60)" }
    $flags -join ' '
}

# "ve 23:45", "v 1:05", "zítra ve 2:30"
function Format-At([DateTime]$local) {
    $day = if ($local.Date -eq [DateTime]::Today) { '' } else { 'zítra ' }
    $preposition = if ($local.Hour -in 2, 3, 4, 12, 13, 14 -or $local.Hour -ge 20) { 've' } else { 'v' }
    "$day$preposition $($local.ToString('H\:mm'))"
}

# ---- Vykreslení ----

function Update-View {
    $running = $null -ne $state.Countdown
    $ui.FormView.Visibility = if ($running) { 'Hidden' } else { 'Visible' }
    $ui.FormView.IsEnabled = -not $running
    $ui.RunView.Visibility = if ($running) { 'Visible' } else { 'Hidden' }

    if ($running) { Update-Countdown } else { Update-Form }
}

function Update-Form {
    $action = Get-Action
    $timed = Test-TimedByWindows $action
    $minutes = Get-Minutes

    # Nastavování IsChecked níže vyvolá Checked/Unchecked; ty se během vykreslení ignorují.
    $state.Rendering = $true
    $ui.ForceToggle.IsEnabled = -not $timed
    $ui.ForceToggle.IsChecked = $timed -or $state.Force
    $ui.HybridToggle.IsEnabled = $action -eq 'Shutdown'
    $ui.HybridToggle.IsChecked = $ui.HybridToggle.IsEnabled -and $state.Hybrid
    $ui.RestoreToggle.IsEnabled = $timed
    $ui.RestoreToggle.IsChecked = $timed -and $state.Restore
    $ui.RestoreFlag.Text = if ($action -eq 'Restart') { '/g' } else { '/sg' }

    foreach ($chip in $ui.Presets.Children) { $chip.IsChecked = $chip.Tag -eq "$minutes" }
    $state.Rendering = $false

    $ui.CommandText.Text = 'shutdown ' + (Get-Arguments)
    $ui.StartButton.Content = 'Naplánovat ' + $words[$action].Accusative
    $ui.StartButton.IsEnabled = $minutes -gt 0
    Update-When

    $brush = if (-not $state.Notice) { 'Muted' } elseif ($state.NoticeIsError) { 'Danger' } else { 'Text' }
    $ui.StatusText.Foreground = $window.FindResource($brush)
    $ui.StatusText.Text =
        if ($state.Notice) { $state.Notice }
        elseif ($timed) { 'Odpočet hlídá Windows, Spáče pak můžeš zavřít.' }
        else { 'Odpočet hlídá Spáč, nech ho běžet na pozadí.' }
}

function Update-When {
    $minutes = Get-Minutes
    $ui.WhenText.Text =
        if ($minutes -gt 0) { "$($words[(Get-Action)].Sentence) $(Format-At ([DateTime]::Now.AddMinutes($minutes)))" }
        else { 'Nastav aspoň jednu minutu.' }
}

function Update-Countdown {
    $countdown = $state.Countdown
    $left = [Math]::Max(0, ($countdown.Due - [DateTime]::UtcNow).TotalSeconds)
    $shown = [TimeSpan]::FromSeconds([Math]::Ceiling($left))

    $ui.RunTitle.Text = $words[$countdown.Action].Sentence + ' za'
    $ui.CountdownText.Text = $shown.ToString($(if ($shown.TotalHours -ge 1) { 'h\:mm\:ss' } else { 'mm\:ss' }))
    $ui.RunWhen.Text = Format-At $countdown.Due.ToLocalTime()
    $ui.RunCommand.Text = 'shutdown ' + $countdown.Arguments

    $fraction = [Math]::Min(1, $left / $countdown.Seconds)
    $ui.BarLeft.Width = [Windows.GridLength]::new($fraction, 'Star')
    $ui.BarGone.Width = [Windows.GridLength]::new(1 - $fraction, 'Star')

    if (-not $state.Notice) {
        $ui.RunStatus.Foreground = $window.FindResource('Muted')
        $ui.RunStatus.Text =
            if (Test-TimedByWindows $countdown.Action) { 'Odpočet hlídá Windows, Spáče můžeš klidně zavřít.' }
            else { 'Odpočet hlídá Spáč. Nech ho běžet, zavřením okna ho zrušíš.' }
    }
}

function Show-Notice($text, [switch]$IsError) {
    $state.Notice = $text
    $state.NoticeIsError = [bool]$IsError
    if ($state.Countdown) {
        $ui.RunStatus.Foreground = $window.FindResource('Danger')
        $ui.RunStatus.Text = $text
    }
    Update-View
}

function Show-Failure($result) {
    $text = if ($result.Message) { $result.Message } else { "shutdown.exe skončil s chybou $($result.Code)." }
    Show-Notice $text -IsError
}

# Uživatel něco změnil ve formuláři: stará hláška už neplatí.
function Reset-Form {
    $state.Notice = $null
    Update-View
}

function Stop-Countdown {
    Clear-Countdown
    $state.Countdown = $null
    $state.Notice = $null
    Update-View
}

# ---- Okno ----

try {
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'Spac.xaml')))
    $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icon)

    $ui = @{}
    'FormView', 'ShutdownTile', 'RestartTile', 'HibernateTile', 'LogOffTile', 'HoursBox', 'MinutesBox', 'Presets',
    'WhenText', 'ForceToggle', 'HybridToggle', 'RestoreToggle', 'RestoreFlag', 'CommandText', 'StartButton',
    'StatusText', 'AbortButton', 'GatewayButton', 'RunView', 'RunTitle', 'CountdownText', 'RunWhen', 'BarLeft', 'BarGone',
    'RunCommand', 'CancelButton', 'RunStatus' | ForEach-Object { $ui[$_] = $window.FindName($_) }

    # Když Spáče pustila Bránocesta, nechala v $env:BRANOCESTA cestu ke svému skriptu. Tlačítko ji otevře
    # a Spáče zavře. Při spuštění vlastním zástupcem proměnná není a tlačítko zůstane schované.
    $gateway = $env:BRANOCESTA
    if ($gateway -and (Split-Path $gateway -Leaf) -eq 'Branocesta.ps1' -and (Test-Path -LiteralPath $gateway)) {
        # Spáč se zavře, až když se okno brány ukáže, a pošle ho dopředu. Kdyby se zavřel hned, Windows by
        # mezitím aktivovaly jiné okno a brána by se otevřela za ním. $handoff.Tag drží čas kliknutí.
        $handoff = [Windows.Threading.DispatcherTimer]::new()
        $handoff.Interval = [TimeSpan]::FromMilliseconds(150)
        $handoff.Add_Tick({
            $shown = $null
            foreach ($process in [Diagnostics.Process]::GetProcessesByName('powershell')) {
                try {
                    if ($process.Id -ne $PID -and $process.StartTime -ge $handoff.Tag -and
                        $process.MainWindowHandle -ne [IntPtr]::Zero) { $shown = $process.Id }
                }
                catch { }   # Proces mezitím skončil nebo k němu není přístup.
                finally { $process.Dispose() }
            }
            if (-not $shown -and [DateTime]::Now -lt $handoff.Tag.AddSeconds(20)) { return }
            $handoff.Stop()
            # Když se brána neukázala, Spáč zůstane otevřený, ať člověk neskončí bez okna.
            if (-not $shown) { return }
            try { [Microsoft.VisualBasic.Interaction]::AppActivate($shown) } catch { }
            $window.Close()
        })
        $ui.GatewayButton.Visibility = 'Visible'
        $ui.GatewayButton.Add_Click({
            if ($handoff.IsEnabled) { return }
            $handoff.Tag = [DateTime]::Now
            # conhost --headless spustí PowerShell bez okna konzole, stejně jako zástupce.
            Start-Process -FilePath "$env:SystemRoot\System32\conhost.exe" -WorkingDirectory (Split-Path $gateway) `
                -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$gateway`""
            $handoff.Start()
        })
    }

    if ($native -and -not $native::IsPwrHibernateAllowed()) {
        $ui.HibernateTile.IsEnabled = $false
        $ui.HibernateTile.ToolTip = 'Hibernace je na tomhle počítači vypnutá.'
    }

    $window.Add_SourceInitialized({
        if (-not $native) { return }
        $hwnd = [Windows.Interop.WindowInteropHelper]::new($window).Handle
        # 20 = tmavý režim, 35 = barva titulku, 34 = barva rámečku; barva je #0F1422 jako COLORREF (0x00BBGGRR).
        # Starší Windows volání jen odmítnou a titulek zůstane výchozí.
        foreach ($attribute in @(20, 1), @(35, 0x0022140F), @(34, 0x0022140F)) {
            $value = $attribute[1]
            $null = $native::DwmSetWindowAttribute($hwnd, $attribute[0], [ref]$value, 4)
        }
    })

    # ---- Formulář ----

    foreach ($tile in $ui.ShutdownTile, $ui.RestartTile, $ui.HibernateTile, $ui.LogOffTile) {
        $tile.Add_Checked({ Reset-Form })
    }

    $toggled = {
        param($toggle)
        if ($state.Rendering) { return }

        $on = $toggle.IsChecked -eq $true
        # shutdown.exe kombinaci /sg /hybrid nebere, takže zapnutí jednoho vypne druhé.
        switch ($toggle.Name) {
            'ForceToggle' { $state.Force = $on }
            'HybridToggle' { $state.Hybrid = $on; if ($on) { $state.Restore = $false } }
            'RestoreToggle' { $state.Restore = $on; if ($on) { $state.Hybrid = $false } }
        }
        Reset-Form
    }
    foreach ($toggle in $ui.ForceToggle, $ui.HybridToggle, $ui.RestoreToggle) {
        $toggle.Add_Checked($toggled)
        $toggle.Add_Unchecked($toggled)
    }

    foreach ($chip in $ui.Presets.Children) {
        $chip.Add_Checked({
            param($preset)
            if ($state.Rendering) { return }

            $minutes = [int]$preset.Tag
            Write-Box $ui.HoursBox ([Math]::Floor($minutes / 60))
            Write-Box $ui.MinutesBox ($minutes % 60)
            Reset-Form
        })
    }

    foreach ($box in $ui.HoursBox, $ui.MinutesBox) {
        $box.Add_TextChanged({
            param($box)
            $digits = $box.Text -replace '[^0-9]'
            if ($digits -ne $box.Text) {
                $box.Text = $digits
                $box.CaretIndex = $digits.Length
                return
            }
            Reset-Form
        })
        $box.Add_LostKeyboardFocus({ param($box) Write-Box $box (Read-Box $box) })
        $box.Add_GotKeyboardFocus({ param($box) $box.SelectAll() })
        # Bez tohohle by první klik myší označení z GotKeyboardFocus hned zase zrušil.
        $box.Add_PreviewMouseLeftButtonDown({
            param($box, $e)
            if ($box.IsKeyboardFocusWithin) { return }
            $null = $box.Focus()
            $e.Handled = $true
        })
        $box.Add_PreviewMouseWheel({
            param($box, $e)
            Step-Box $box ([Math]::Sign($e.Delta) * $(if ($box.Name -eq 'HoursBox') { 1 } else { 5 }))
            $e.Handled = $true
        })
        $box.Add_PreviewKeyDown({
            param($box, $e)
            if ($e.Key -ne 'Up' -and $e.Key -ne 'Down') { return }
            Step-Box $box $(if ($e.Key -eq 'Up') { 1 } else { -1 })
            $e.Handled = $true
        })
    }

    # ---- Odpočet ----

    $ui.StartButton.Add_Click({
        $minutes = Get-Minutes
        if ($state.Countdown -or $minutes -eq 0) { return }

        $countdown = @{ Action = Get-Action; Seconds = $minutes * 60; Arguments = Get-Arguments }
        $timed = Test-TimedByWindows $countdown.Action
        if ($timed) {
            $result = Invoke-Shutdown $countdown.Arguments
            if ($result.Code -eq $alreadyScheduled) {
                # Už něco naplánovaného je (třeba z příkazové řádky): nové nastavení ho nahradí.
                $null = Invoke-Shutdown '/a'
                $result = Invoke-Shutdown $countdown.Arguments
            }
            if ($result.Code -ne 0) {
                Show-Failure $result
                return
            }
        }

        $countdown.Due = [DateTime]::UtcNow.AddSeconds($countdown.Seconds)
        if ($timed) { Save-Countdown $countdown }
        $state.Countdown = $countdown
        $state.Notice = $null
        Update-View
    })

    $ui.CancelButton.Add_Click({
        if (-not $state.Countdown) { return }

        if (Test-TimedByWindows $state.Countdown.Action) {
            $result = Invoke-Shutdown '/a'
            if ($result.Code -ne 0 -and $result.Code -ne $nothingScheduled) {
                Show-Failure $result
                return
            }
        }
        Stop-Countdown
    })

    # Zruší cokoli, co je ve Windows naplánované, i když to nenastavil Spáč.
    $ui.AbortButton.Add_Click({
        $result = Invoke-Shutdown '/a'
        if ($result.Code -eq 0) { Show-Notice 'Naplánované vypnutí je zrušené.' }
        elseif ($result.Code -eq $nothingScheduled) { Show-Notice 'Nic naplánovaného není, není co rušit.' }
        else { Show-Failure $result }
    })

    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        $countdown = $state.Countdown
        if (-not $countdown) { Update-When; return }
        if ($countdown.Due -gt [DateTime]::UtcNow) { Update-Countdown; return }

        Stop-Countdown
        # Vypnutí a restart v tu chvíli provedou Windows samy; hibernaci a odhlášení spouští Spáč.
        if (-not (Test-TimedByWindows $countdown.Action)) {
            $result = Invoke-Shutdown $countdown.Arguments
            if ($result.Code -ne 0) { Show-Failure $result }
        }
    })

    $state.Countdown = Read-Countdown
    Update-View
    $timer.Start()
    $null = $window.ShowDialog()
    $timer.Stop()
}
catch {
    # Konzole je schovaná, takže chybu jinak nikdo neuvidí.
    $null = [Windows.MessageBox]::Show("$_", 'Spáč', 'OK', 'Error')
}
