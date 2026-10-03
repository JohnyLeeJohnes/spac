# End-to-end test Spáče přes UI Automation:
#   powershell -ExecutionPolicy Bypass -File tests/e2e.ps1
#
# POZOR: test doopravdy plánuje vypnutí (nejdřív za 3 hodiny) a hned ho zase ruší.
# Na konci vždy zavolá shutdown /a, takže zruší i vypnutí, které sis naplánoval sám.
# Hibernace ani odhlášení se nikdy nespustí, jen se u nich zapne a zruší odpočet.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [Windows.Automation.AutomationElement]
$app = Join-Path $PSScriptRoot '..\Spac.ps1'
$pending = Join-Path $env:LOCALAPPDATA 'Spac\pending'
$script:fail = 0

function Launch {
    $p = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList `
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$app`""
    $ofProcess = New-Object Windows.Automation.PropertyCondition ($AE::ProcessIdProperty, $p.Id)
    $script:root = $null
    for ($i = 0; $i -lt 200 -and -not $script:root; $i++) {
        Start-Sleep -Milliseconds 50
        $script:root = $AE::RootElement.FindFirst([Windows.Automation.TreeScope]::Children, $ofProcess)
    }
    if (-not $script:root) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue; throw 'Okno Spáče se neobjevilo.' }
    Start-Sleep -Milliseconds 500
    $p
}
function Find($id) {
    $byId = New-Object Windows.Automation.PropertyCondition ($AE::AutomationIdProperty, $id)
    $script:root.FindFirst([Windows.Automation.TreeScope]::Descendants, $byId)
}
function Text($id) { $e = Find $id; if ($e) { $e.Current.Name } else { '<nenalezeno>' } }
function Value($id) { (Find $id).GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value }
function Toggle($id) { (Find $id).GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Toggle(); Start-Sleep -Milliseconds 250 }
function Pick($id) { (Find $id).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 250 }
function SetValue($id, $v) { (Find $id).GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($v); Start-Sleep -Milliseconds 250 }
function Invoke($id) { (Find $id).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 1200 }
function Preset($label) {
    $byName = New-Object Windows.Automation.PropertyCondition ($AE::NameProperty, $label)
    $script:root.FindFirst([Windows.Automation.TreeScope]::Descendants, $byName).GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 250
}
function Check($what, $actual, $expected) {
    if ($actual -eq $expected) { "ok    $what = $actual" }
    else { $script:fail++; "FAIL  $what = '$actual' (čekáno '$expected')" }
}
# Zeptá se Windows, jestli je něco naplánované: druhé plánování musí skončit kódem 1190.
function Scheduled {
    & shutdown.exe /s /t 86000 2>$null | Out-Null
    $code = $LASTEXITCODE
    if ($code -eq 0) { & shutdown.exe /a | Out-Null }
    $code -eq 1190
}

& shutdown.exe /a 2>$null | Out-Null
$p = Launch
try {
    # --- náhled příkazu pro všechny kombinace ---
    Check 'výchozí příkaz' (Text CommandText) 'shutdown /s /f /t 1800'
    Check 'výchozí tlačítko' (Find StartButton).Current.Name 'Naplánovat vypnutí'
    Check '/f u vypnutí nejde vypnout' (Find ForceToggle).Current.IsEnabled $false

    Toggle HybridToggle
    Check '+ hybrid' (Text CommandText) 'shutdown /s /hybrid /f /t 1800'
    Toggle RestoreToggle
    Check '+ obnovit aplikace (vypne hybrid)' (Text CommandText) 'shutdown /sg /f /t 1800'
    Toggle HybridToggle
    Check '+ hybrid (vypne obnovu)' (Text CommandText) 'shutdown /s /hybrid /f /t 1800'
    Toggle RestoreToggle

    Pick RestartTile
    Check 'restart' (Text CommandText) 'shutdown /g /f /t 1800'
    Check 'restart: tlačítko' (Find StartButton).Current.Name 'Naplánovat restart'
    Check 'hybrid u restartu vypnutý' (Find HybridToggle).Current.IsEnabled $false
    Toggle RestoreToggle
    Check 'restart bez obnovy' (Text CommandText) 'shutdown /r /f /t 1800'

    Pick LogOffTile
    Check 'odhlášení' (Text CommandText) 'shutdown /l'
    Toggle ForceToggle
    Check 'odhlášení + force' (Text CommandText) 'shutdown /l /f'
    Check 'odhlášení: nápověda' (Text StatusText) 'Odpočet hlídá Spáč, nech ho běžet na pozadí.'
    $canHibernate = (Find HibernateTile).Current.IsEnabled
    if ($canHibernate) {
        Pick HibernateTile
        Check 'hibernace + force' (Text CommandText) 'shutdown /h /f'
    }

    # --- čas ---
    Pick ShutdownTile
    Preset '2 h'
    Check 'předvolba 2 h' (Text CommandText) 'shutdown /s /f /t 7200'
    Preset '1,5 h'
    Check 'předvolba 1,5 h' "$(Value HoursBox):$(Value MinutesBox)" '1:30'
    Check 'předvolba 1,5 h: příkaz' (Text CommandText) 'shutdown /s /f /t 5400'
    SetValue MinutesBox '0'
    SetValue HoursBox '0'
    Check 'nula minut: tlačítko vypnuté' (Find StartButton).Current.IsEnabled $false
    Check 'nula minut: nápověda' (Text WhenText) 'Nastav aspoň jednu minutu.'
    SetValue HoursBox '99'
    SetValue MinutesBox '7x'
    Check 'ořez na 23 h + jen číslice' (Text CommandText) 'shutdown /s /f /t 83220'

    # --- odpočet, který hlídá Spáč (nic se nespustí, hned se ruší) ---
    if ($canHibernate) {
        Pick HibernateTile
        Invoke StartButton
        Check 'hibernace: příkaz v odpočtu' (Text RunCommand) 'shutdown /h /f'
        Check 'hibernace: nadpis' (Text RunTitle) 'Počítač přejde do hibernace za'
        Check 'hibernace: stav' (Text RunStatus) 'Odpočet hlídá Spáč. Nech ho běžet, zavřením okna ho zrušíš.'
        Check 'hibernace: nic se neukládá' (Test-Path $pending) $false
        Check 'hibernace: Windows nic naplánovaného nemají' (Scheduled) $false
        Invoke CancelButton
        Check 'hibernace: po zrušení zpět formulář' (Find StartButton).Current.IsEnabled $true
        Pick ShutdownTile
    }

    # --- skutečné naplánování (za 23 h 7 min) ---
    Invoke StartButton
    Check 'stavový soubor existuje' (Test-Path $pending) $true
    Check 'příkaz v odpočtu' (Text RunCommand) 'shutdown /s /f /t 83220'
    Check 'nadpis odpočtu' (Text RunTitle) 'Počítač se vypne za'
    Check 'stav odpočtu' (Text RunStatus) 'Odpočet hlídá Windows, Spáče můžeš klidně zavřít.'
    Check 'odpočet běží' ((Text CountdownText) -match '^23:0[67]:\d\d$') $true
    Check 'Windows mají vypnutí naplánované' (Scheduled) $true

    # --- zavřít a znovu otevřít: odpočet musí být zpět ---
    Stop-Process -Id $p.Id; Start-Sleep -Milliseconds 500
    $p = Launch
    Check 'po znovuotevření běží odpočet' (Text RunCommand) 'shutdown /s /f /t 83220'

    Invoke CancelButton
    Check 'po zrušení zmizel stavový soubor' (Test-Path $pending) $false
    Check 'po zrušení zpět formulář' (Find StartButton).Current.IsEnabled $true
    Check 'po zrušení Windows nic naplánovaného nemají' (Scheduled) $false

    # --- přepsání cizího naplánovaného vypnutí (1190 -> /a -> znovu) ---
    & shutdown.exe /s /t 86000 | Out-Null
    Preset '3 h'
    Invoke StartButton
    Check 'nahrazení cizího plánu' (Text RunCommand) 'shutdown /s /f /t 10800'
    Check 'nahrazení: Windows mají vypnutí naplánované' (Scheduled) $true
    Invoke CancelButton
    Check 'nahrazení: po zrušení nic nezbývá' (Scheduled) $false

    # --- tlačítko "Zrušit naplánované vypnutí" (/a) ---
    & shutdown.exe /s /t 86000 | Out-Null
    Invoke AbortButton
    Check '/a: hláška' (Text StatusText) 'Naplánované vypnutí je zrušené.'
    Check '/a: Windows nic naplánovaného nemají' (Scheduled) $false
    Invoke AbortButton
    Check '/a bez plánu: hláška' (Text StatusText) 'Nic naplánovaného není, není co rušit.'
    Pick RestartTile
    Check 'hláška po změně formuláře zmizí' (Text StatusText) 'Odpočet hlídá Windows, Spáče pak můžeš zavřít.'
}
finally {
    & shutdown.exe /a 2>$null | Out-Null
    if (-not $p.HasExited) { Stop-Process -Id $p.Id }
    if (Test-Path $pending) { [IO.File]::Delete($pending) }
}
"---"; "chyb: $script:fail"
exit $script:fail
