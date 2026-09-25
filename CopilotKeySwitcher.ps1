<#
.SYNOPSIS
    Choose which app the Copilot key (and Win+C) opens on Windows 11.

.DESCRIPTION
    Sets the "Set Copilot Hardware Key" policy for the current user. This works
    for apps that don't appear in Settings > Personalization > Text input >
    Customize Copilot key on keyboard.

    Run with no arguments for a window. Use -List, -App, or -Reset from a terminal.

.EXAMPLE
    .\CopilotKeySwitcher.ps1
    .\CopilotKeySwitcher.ps1 -List
    .\CopilotKeySwitcher.ps1 -App Claude
    .\CopilotKeySwitcher.ps1 -App 'Claude_pzs8sxrjxfjjc!Claude'
    .\CopilotKeySwitcher.ps1 -Reset
#>
[CmdletBinding(DefaultParameterSetName = 'Gui')]
param(
    [Parameter(ParameterSetName = 'List')] [switch] $List,
    [Parameter(ParameterSetName = 'Set', Mandatory)] [string] $App,
    [Parameter(ParameterSetName = 'Reset')] [switch] $Reset,
    [Parameter(ParameterSetName = 'All')] [switch] $All,
    # Internal: SID of the user whose setting to change, passed to the elevated copy.
    [string] $UserSid,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$PolicySubKey = 'Software\Policies\Microsoft\Windows\CopilotKey'
$PolicyValue  = 'SetCopilotHardwareKey'

# Display name, regex matched against Start menu app names. Order is display order.
$KnownApps = @(
    @{ Name = 'Claude';                Match = '^Claude$' }
    @{ Name = 'ChatGPT';               Match = '^ChatGPT$' }
    @{ Name = 'Microsoft Copilot';     Match = '^Copilot$' }
    @{ Name = 'Microsoft 365 Copilot'; Match = '^(Microsoft 365 Copilot|Microsoft 365 \(Office\))$' }
    @{ Name = 'Perplexity';            Match = '^Perplexity' }
    @{ Name = 'Gemini';                Match = '^(Google )?Gemini$' }
    @{ Name = 'Grok';                  Match = '^Grok$' }
    @{ Name = 'Codex';                 Match = '^Codex$' }
    @{ Name = 'Mistral Le Chat';       Match = '^(Le Chat|Mistral)' }
    @{ Name = 'DeepSeek';              Match = '^DeepSeek' }
)

function Get-CurrentSid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Test-IsAdmin {
    $p = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
    $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PolicyPath([string] $Sid) {
    "Registry::HKEY_USERS\$Sid\$PolicySubKey"
}

function Get-CurrentSetting([string] $Sid) {
    $item = Get-ItemProperty -Path (Get-PolicyPath $Sid) -Name $PolicyValue -ErrorAction SilentlyContinue
    if ($item) { $item.$PolicyValue } else { $null }
}

function Get-StartAppList {
    # Packaged apps have an AppID of the form PackageFamilyName!AppId.
    Get-StartApps | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; AppID = $_.AppID; Packaged = $_.AppID -like '*!*' }
    }
}

function Find-KnownApps($StartApps) {
    foreach ($known in $KnownApps) {
        $hit = $StartApps | Where-Object { $_.Name -match $known.Match } |
            Sort-Object @{ Expression = 'Packaged'; Descending = $true } | Select-Object -First 1
        if ($hit) { [pscustomobject]@{ Name = $known.Name; AppID = $hit.AppID; Packaged = $hit.Packaged } }
    }
}

function Resolve-AppId([string] $NameOrId) {
    if ($NameOrId -like '*!*') { return $NameOrId }
    $apps = Get-StartAppList
    $known = Find-KnownApps $apps | Where-Object { $_.Name -eq $NameOrId }
    if ($known) { return $known.AppID }
    $exact = @($apps | Where-Object { $_.Name -eq $NameOrId })
    if ($exact.Count -ge 1) { return $exact[0].AppID }
    throw "No installed app named '$NameOrId'. Run with -List to see names, or pass an app ID."
}

# Writes (or clears, when $AppId is empty) the policy. Elevates when needed.
function Set-CopilotKeyTarget([string] $AppId, [string] $Sid) {
    if (Test-IsAdmin) {
        $path = Get-PolicyPath $Sid
        if ($AppId) {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            Set-ItemProperty -Path $path -Name $PolicyValue -Value $AppId -Type String
        } elseif (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name $PolicyValue -ErrorAction SilentlyContinue
        }
        return $true
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-UserSid', $Sid, '-Quiet')
    if ($AppId) { $argList += @('-App', "`"$AppId`"") } else { $argList += '-Reset' }
    try {
        $proc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe')-ArgumentList $argList -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    } catch {
        return $false  # UAC prompt declined
    }
    $proc.ExitCode -eq 0
}

function Show-Gui {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $sid = Get-CurrentSid
    $allApps = @(Get-StartAppList)
    $aiApps = @(Find-KnownApps $allApps)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Copilot Key Switcher'
    $form.Size = New-Object System.Drawing.Size(520, 560)
    $form.MinimumSize = New-Object System.Drawing.Size(420, 420)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object System.Windows.Forms.Padding(12)
    $layout.ColumnCount = 1
    $layout.RowCount = 7
    foreach ($style in 'AutoSize', 'AutoSize', 'AutoSize', 'Percent', 'AutoSize', 'AutoSize', 'AutoSize') {
        $rs = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::$style)
        if ($style -eq 'Percent') { $rs.Height = 100 }
        [void]$layout.RowStyles.Add($rs)
    }
    $form.Controls.Add($layout)

    $current = New-Object System.Windows.Forms.Label
    $current.AutoSize = $true
    $current.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $layout.Controls.Add($current)

    $showAll = New-Object System.Windows.Forms.CheckBox
    $showAll.Text = 'Show all installed apps'
    $showAll.AutoSize = $true
    $showAll.Checked = ($aiApps.Count -eq 0)
    $layout.Controls.Add($showAll)

    $filter = New-Object System.Windows.Forms.TextBox
    $filter.Dock = 'Fill'
    $layout.Controls.Add($filter)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.HideSelection = $false
    $list.Dock = 'Fill'
    [void]$list.Columns.Add('App', 180)
    [void]$list.Columns.Add('App ID', 290)
    $layout.Controls.Add($list)

    $idLabel = New-Object System.Windows.Forms.Label
    $idLabel.Text = 'App ID (pick above or paste your own):'
    $idLabel.AutoSize = $true
    $idLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 2)
    $layout.Controls.Add($idLabel)

    $idBox = New-Object System.Windows.Forms.TextBox
    $idBox.Dock = 'Fill'
    $layout.Controls.Add($idBox)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.Dock = 'Fill'
    $buttons.AutoSize = $true
    $buttons.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text = 'Apply'
    $applyBtn.AutoSize = $true
    $resetBtn = New-Object System.Windows.Forms.Button
    $resetBtn.Text = 'Reset to Windows default'
    $resetBtn.AutoSize = $true
    $buttons.Controls.AddRange(@($applyBtn, $resetBtn))
    $layout.Controls.Add($buttons)
    $form.AcceptButton = $applyBtn

    $setCueBanner = {
        param($box, $text)
        # EM_SETCUEBANNER shows placeholder text in an empty TextBox.
        if (-not ('CopilotKeySwitcher.CueBanner' -as [type])) {
            Add-Type -Namespace CopilotKeySwitcher -Name CueBanner -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern System.IntPtr SendMessage(System.IntPtr h, int m, int w, string l);'
        }
        [void][CopilotKeySwitcher.CueBanner]::SendMessage($box.Handle, 0x1501, 1, $text)
    }
    $form.Add_Shown({ & $setCueBanner $filter 'Search apps' })

    $refreshCurrent = {
        $value = Get-CurrentSetting $sid
        if (-not $value) {
            $current.Text = 'Copilot key: Windows default (set in Settings)'
        } else {
            $match = $allApps | Where-Object { $_.AppID -eq $value } | Select-Object -First 1
            $name = if ($match) { $match.Name } else { 'app not installed' }
            $current.Text = "Copilot key: $name`n$value"
        }
    }

    $fillList = {
        $list.BeginUpdate()
        $list.Items.Clear()
        $source = if ($showAll.Checked) { $allApps } else { $aiApps }
        $term = $filter.Text.Trim()
        foreach ($a in $source) {
            if ($term -and $a.Name -notlike "*$term*" -and $a.AppID -notlike "*$term*") { continue }
            $item = New-Object System.Windows.Forms.ListViewItem($a.Name)
            [void]$item.SubItems.Add($a.AppID)
            if (-not $a.Packaged) { $item.ForeColor = [System.Drawing.Color]::Gray }
            [void]$list.Items.Add($item)
        }
        $list.EndUpdate()
    }

    $list.Add_SelectedIndexChanged({
        if ($list.SelectedItems.Count) { $idBox.Text = $list.SelectedItems[0].SubItems[1].Text }
    })
    $showAll.Add_CheckedChanged($fillList)
    $filter.Add_TextChanged($fillList)

    $finish = {
        param($ok)
        if (-not $ok) {
            [void][System.Windows.Forms.MessageBox]::Show($form, 'The change needs administrator approval and was not saved.', 'Copilot Key Switcher', 'OK', 'Warning')
            return
        }
        & $refreshCurrent
        $answer = [System.Windows.Forms.MessageBox]::Show($form, "Saved. Sign out and back in for the Copilot key to pick it up.`n`nSign out now?", 'Copilot Key Switcher', 'YesNo', 'Information')
        if ($answer -eq 'Yes') { & shutdown.exe /l }
    }

    $applyBtn.Add_Click({
        $id = $idBox.Text.Trim()
        if (-not $id) {
            [void][System.Windows.Forms.MessageBox]::Show($form, 'Pick an app or paste an app ID first.', 'Copilot Key Switcher')
            return
        }
        if ($id -notlike '*!*') {
            $warn = "This app isn't a packaged (Store/MSIX) app. Windows may ignore it and open search instead.`n`nSave it anyway?"
            if ([System.Windows.Forms.MessageBox]::Show($form, $warn, 'Copilot Key Switcher', 'YesNo', 'Warning') -ne 'Yes') { return }
        }
        & $finish (Set-CopilotKeyTarget $id $sid)
    })
    $resetBtn.Add_Click({ & $finish (Set-CopilotKeyTarget '' $sid) })

    & $refreshCurrent
    & $fillList
    [void]$form.ShowDialog()
}

# --- entry point ---
if (-not $UserSid) { $UserSid = Get-CurrentSid }

switch ($PSCmdlet.ParameterSetName) {
    'List' {
        $value = Get-CurrentSetting $UserSid
        "Current: $(if ($value) { $value } else { 'Windows default' })"
        ''
        $found = @(Find-KnownApps (Get-StartAppList))
        if ($found.Count) { $found | Format-Table Name, AppID -AutoSize | Out-String -Width 300 }
        else { 'No known AI apps found. Use -All to list every installed app.' }
    }
    'All'   { Get-StartAppList | Format-Table Name, AppID -AutoSize | Out-String -Width 300 }
    'Set' {
        $id = Resolve-AppId $App
        if (-not (Set-CopilotKeyTarget $id $UserSid)) { Write-Error 'Needs administrator approval. Nothing changed.'; exit 1 }
        if (-not $Quiet) { "Copilot key now opens: $id"; 'Sign out and back in to apply.' }
    }
    'Reset' {
        if (-not (Set-CopilotKeyTarget '' $UserSid)) { Write-Error 'Needs administrator approval. Nothing changed.'; exit 1 }
        if (-not $Quiet) { 'Copilot key reset to the Windows default. Sign out and back in to apply.' }
    }
    'Gui'   { Show-Gui }
}
exit 0
