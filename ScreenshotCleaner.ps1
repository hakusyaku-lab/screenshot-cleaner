<#
  スクショ整理 (ScreenshotCleaner)
  ------------------------------------------------------------
  使い方:
    ss                       … 一覧ウィンドウを開く（今日のスクショ）
    ss -List                 … 今日のスクショをコンソールに一覧表示
    ss -List -Days 3         … 直近3日分を一覧表示
    ss -Delete -Days 1       … 今日のスクショをごみ箱へ（確認あり）
    ss -Delete -Days 7 -Older… 直近7日より古いものをごみ箱へ
    オプション: -Permanent（ごみ箱を使わず完全削除） -Force（確認なし）
                -Folder "パス"（対象フォルダを指定）
    ss -Install / ss -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$List,
    [switch]$Delete,
    [ValidateRange(1, 365)][int]$Days = 1,
    [switch]$Older,
    [switch]$Permanent,
    [switch]$Force,
    [string]$Folder,
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$AppName     = 'ScreenshotCleaner'
$AppDir      = Join-Path $env:LOCALAPPDATA $AppName
$FolderFile  = Join-Path $AppDir 'folder.txt'
$ImageExt    = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')
$ShortcutName = 'スクショ整理.lnk'

# ---------------------------------------------------------------- 共通
function Get-ScreenshotFolder {
    if ($Folder) { return $Folder }
    if (Test-Path -LiteralPath $FolderFile) {
        $saved = (Get-Content -LiteralPath $FolderFile -Raw -Encoding UTF8).Trim()
        if ($saved -and (Test-Path -LiteralPath $saved)) { return $saved }
    }
    # Windows の「スクリーンショット」既知フォルダ（OneDrive へ移動していても追従）
    $guid = '{B7BEDE81-DF94-4682-A7D8-57A52620B86F}'
    $key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    try {
        $v = (Get-ItemProperty -Path $key -Name $guid -ErrorAction Stop).$guid
        if ($v) {
            $p = [Environment]::ExpandEnvironmentVariables($v)
            if (Test-Path -LiteralPath $p) { return $p }
        }
    } catch {}
    $pics = [Environment]::GetFolderPath('MyPictures')
    foreach ($name in @('Screenshots', 'スクリーンショット')) {
        $p = Join-Path $pics $name
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $pics 'Screenshots')
}

function Save-ScreenshotFolder([string]$path) {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    Set-Content -LiteralPath $FolderFile -Value $path -Encoding UTF8
}

# 直近N日 = (N-1)日前の0:00以降。-Older はそれより前。
function Get-Targets([string]$dir, [int]$n, [bool]$old) {
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $cutoff = (Get-Date).Date.AddDays( - ($n - 1))
    @(Get-ChildItem -LiteralPath $dir -File |
        Where-Object { $ImageExt -contains $_.Extension.ToLower() } |
        Where-Object { if ($old) { $_.LastWriteTime -lt $cutoff } else { $_.LastWriteTime -ge $cutoff } } |
        Sort-Object LastWriteTime -Descending)
}

function Format-Size([double]$b) {
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    return ('{0:N0} KB' -f [Math]::Ceiling($b / 1KB))
}

function Remove-Shot([string]$path, [bool]$perm) {
    if ($perm) {
        Remove-Item -LiteralPath $path -Force
    } else {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

function Get-RangeLabel([int]$n, [bool]$old) {
    $r = if ($n -eq 1) { '今日' } else { "直近${n}日" }
    if ($old) { "${r}より古いもの" } else { $r }
}

# ---------------------------------------------------------------- インストール
if ($Install) {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $target = Join-Path $AppDir 'ScreenshotCleaner.ps1'
    if ($PSCommandPath -ne $target) { Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force }
    try { Unblock-File -LiteralPath $target } catch {}

    # ss コマンド（cmd / PowerShell / Win+R から使える）
    $cmd = @'
@echo off
if "%~1"=="" (
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ScreenshotCleaner.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ScreenshotCleaner.ps1" %*
)
'@
    Set-Content -LiteralPath (Join-Path $AppDir 'ss.cmd') -Value $cmd -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if (($userPath -split ';') -notcontains $AppDir) {
        $newPath = (($userPath.TrimEnd(';'), $AppDir) | Where-Object { $_ }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }

    # デスクトップとスタートメニューにボタン（ショートカット）
    $ws = New-Object -ComObject WScript.Shell
    foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        $lnk = $ws.CreateShortcut((Join-Path $d $ShortcutName))
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
        $lnk.WorkingDirectory = $AppDir
        $lnk.IconLocation = (Join-Path $env:WINDIR 'System32\imageres.dll') + ',67'
        $lnk.Description = '今日のスクリーンショットを一覧・削除'
        $lnk.Save()
    }

    Write-Host ''
    Write-Host 'インストール完了' -ForegroundColor Green
    Write-Host "  ・デスクトップとスタートメニューに「スクショ整理」を追加しました"
    Write-Host "  ・新しく開いたターミナル / Win+R で  ss  と入力しても起動できます"
    Write-Host "  ・対象フォルダ: $(Get-ScreenshotFolder)"
    return
}

if ($Uninstall) {
    foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        $p = Join-Path $d $ShortcutName
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) {
        $newPath = ($userPath -split ';' | Where-Object { $_ -and $_ -ne $AppDir }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }
    if (Test-Path -LiteralPath $AppDir) { Remove-Item -LiteralPath $AppDir -Recurse -Force }
    Write-Host 'アンインストールしました（スクリーンショット自体は消していません）' -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------- コマンド版
if ($List -or $Delete) {
    $dir   = Get-ScreenshotFolder
    $files = Get-Targets $dir $Days $Older.IsPresent
    $label = Get-RangeLabel $Days $Older.IsPresent
    Write-Host "フォルダ: $dir" -ForegroundColor DarkGray
    if ($files.Count -eq 0) { Write-Host "${label}のスクリーンショットはありません。"; return }

    $files | ForEach-Object {
        '{0:MM/dd HH:mm}  {1,10}  {2}' -f $_.LastWriteTime, (Format-Size $_.Length), $_.Name
    } | Write-Host
    $total = ($files | Measure-Object Length -Sum).Sum
    Write-Host ("{0}: {1} 件 / {2}" -f $label, $files.Count, (Format-Size $total)) -ForegroundColor Cyan

    if ($Delete) {
        $how = if ($Permanent) { '完全に削除' } else { 'ごみ箱に移動' }
        if (-not $Force) {
            $ans = Read-Host "上の $($files.Count) 件を${how}します。よろしいですか？ (y/N)"
            if ($ans -notmatch '^(y|yes)$') { Write-Host '中止しました。'; return }
        }
        $ok = 0; $ng = 0
        foreach ($f in $files) {
            try { Remove-Shot $f.FullName $Permanent.IsPresent; $ok++ }
            catch { $ng++; Write-Host "失敗: $($f.Name) - $($_.Exception.Message)" -ForegroundColor Red }
        }
        Write-Host "$ok 件を${how}しました。" -ForegroundColor Green
        if ($ng) { Write-Host "$ng 件は削除できませんでした。" -ForegroundColor Red }
    }
    return
}

# ---------------------------------------------------------------- ウィンドウ版
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ThumbW = 200; $ThumbH = 125
$script:CurrentFolder = Get-ScreenshotFolder
$script:Bulk = $false

function New-Thumb([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)   # ファイルをロックしないようメモリから読む
    $ms = New-Object IO.MemoryStream(, $bytes)
    try {
        $img = [Drawing.Image]::FromStream($ms)
        $bmp = New-Object Drawing.Bitmap $ThumbW, $ThumbH
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.Clear([Drawing.Color]::FromArgb(240, 240, 240))
        $scale = [Math]::Min($ThumbW / $img.Width, $ThumbH / $img.Height)
        $dw = [int]($img.Width * $scale); $dh = [int]($img.Height * $scale)
        $g.DrawImage($img, [int](($ThumbW - $dw) / 2), [int](($ThumbH - $dh) / 2), $dw, $dh)
        $g.Dispose(); $img.Dispose()
        return $bmp
    } finally { $ms.Dispose() }
}

function New-Placeholder {
    $bmp = New-Object Drawing.Bitmap $ThumbW, $ThumbH
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.Clear([Drawing.Color]::FromArgb(225, 225, 225))
    $f = New-Object Drawing.Font('Yu Gothic UI', 11)
    $g.DrawString('プレビューなし', $f, [Drawing.Brushes]::Gray, 50, 52)
    $g.Dispose(); $f.Dispose()
    return $bmp
}

try {
    $form = New-Object Windows.Forms.Form
    $form.Text = 'スクショ整理'
    $form.Size = New-Object Drawing.Size(1000, 700)
    $form.MinimumSize = New-Object Drawing.Size(720, 480)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Yu Gothic UI', 10)
    $form.KeyPreview = $true

    # --- 上部：期間・フォルダ
    $top = New-Object Windows.Forms.FlowLayoutPanel
    $top.Dock = 'Top'; $top.AutoSize = $true; $top.Padding = '8,8,8,4'; $top.WrapContents = $true

    $lblRange = New-Object Windows.Forms.Label
    $lblRange.Text = '期間:'; $lblRange.AutoSize = $true; $lblRange.Margin = '3,8,3,3'

    $combo = New-Object Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'; $combo.Width = 170
    [void]$combo.Items.Add('今日')
    foreach ($n in 2..7) { [void]$combo.Items.Add("直近${n}日") }
    $combo.SelectedIndex = 0

    $rbRecent = New-Object Windows.Forms.RadioButton
    $rbRecent.Text = 'この期間のもの'; $rbRecent.AutoSize = $true; $rbRecent.Checked = $true; $rbRecent.Margin = '12,6,3,3'
    $rbOlder = New-Object Windows.Forms.RadioButton
    $rbOlder.Text = 'それより古いもの'; $rbOlder.AutoSize = $true; $rbOlder.Margin = '3,6,3,3'

    $btnReload = New-Object Windows.Forms.Button
    $btnReload.Text = '更新 (F5)'; $btnReload.AutoSize = $true; $btnReload.Margin = '16,3,3,3'
    $btnOpen = New-Object Windows.Forms.Button
    $btnOpen.Text = 'フォルダを開く'; $btnOpen.AutoSize = $true
    $btnChange = New-Object Windows.Forms.Button
    $btnChange.Text = 'フォルダ変更…'; $btnChange.AutoSize = $true

    $top.Controls.AddRange(@($lblRange, $combo, $rbRecent, $rbOlder, $btnReload, $btnOpen, $btnChange))

    # --- 中央：サムネイル一覧
    $imgList = New-Object Windows.Forms.ImageList
    $imgList.ImageSize = New-Object Drawing.Size($ThumbW, $ThumbH)
    $imgList.ColorDepth = 'Depth32Bit'

    $lv = New-Object Windows.Forms.ListView
    $lv.Dock = 'Fill'; $lv.View = 'LargeIcon'; $lv.CheckBoxes = $true
    $lv.LargeImageList = $imgList; $lv.ShowItemToolTips = $true; $lv.MultiSelect = $true

    # --- 下部：状態・操作
    $bottom = New-Object Windows.Forms.FlowLayoutPanel
    $bottom.Dock = 'Bottom'; $bottom.AutoSize = $true; $bottom.Padding = '8,4,8,8'; $bottom.WrapContents = $true

    $btnAll = New-Object Windows.Forms.Button
    $btnAll.Text = 'すべてチェック'; $btnAll.AutoSize = $true
    $btnNone = New-Object Windows.Forms.Button
    $btnNone.Text = 'チェック解除'; $btnNone.AutoSize = $true
    $chkPerm = New-Object Windows.Forms.CheckBox
    $chkPerm.Text = '完全に削除（ごみ箱を使わない）'; $chkPerm.AutoSize = $true; $chkPerm.Margin = '16,7,3,3'
    $btnDel = New-Object Windows.Forms.Button
    $btnDel.Text = 'チェックしたものを削除'; $btnDel.AutoSize = $true; $btnDel.Margin = '16,3,3,3'
    $btnDel.BackColor = [Drawing.Color]::FromArgb(200, 55, 55); $btnDel.ForeColor = [Drawing.Color]::White
    $btnDel.FlatStyle = 'Flat'
    $status = New-Object Windows.Forms.Label
    $status.AutoSize = $true; $status.Margin = '16,8,3,3'

    $bottom.Controls.AddRange(@($btnAll, $btnNone, $chkPerm, $btnDel, $status))

    $form.Controls.Add($lv)
    $form.Controls.Add($top)
    $form.Controls.Add($bottom)

    $placeholder = New-Placeholder

    function Update-Status {
        $all = 0.0; $chk = 0.0; $nChk = 0
        foreach ($it in $lv.Items) {
            $all += $it.Tag.Length
            if ($it.Checked) { $chk += $it.Tag.Length; $nChk++ }
        }
        $label = Get-RangeLabel ($combo.SelectedIndex + 1) $rbOlder.Checked
        if ($lv.Items.Count -eq 0) {
            $status.Text = "${label}のスクリーンショットはありません　｜　$script:CurrentFolder"
        } else {
            $status.Text = "${label}: $($lv.Items.Count) 件 / $(Format-Size $all)　｜　チェック: $nChk 件 / $(Format-Size $chk)"
        }
        $form.Text = "スクショ整理 — $script:CurrentFolder"
    }

    function Load-List {
        $form.Cursor = 'WaitCursor'
        $lv.BeginUpdate()
        $lv.Items.Clear()
        foreach ($im in @($imgList.Images)) { $im.Dispose() }
        $imgList.Images.Clear()

        if (-not (Test-Path -LiteralPath $script:CurrentFolder)) {
            $lv.EndUpdate(); $form.Cursor = 'Default'
            $status.Text = "フォルダが見つかりません: $script:CurrentFolder（「フォルダ変更…」で指定してください）"
            return
        }

        $files = Get-Targets $script:CurrentFolder ($combo.SelectedIndex + 1) $rbOlder.Checked
        $i = 0
        foreach ($f in $files) {
            try { $thumb = New-Thumb $f.FullName } catch { $thumb = $placeholder.Clone() }
            $imgList.Images.Add($f.FullName, $thumb)
            $text = '{0:MM/dd HH:mm}  {1}' -f $f.LastWriteTime, (Format-Size $f.Length)
            $item = New-Object Windows.Forms.ListViewItem($text)
            $item.ImageKey = $f.FullName
            $item.Tag = $f
            $item.ToolTipText = $f.Name
            [void]$lv.Items.Add($item)
            $i++
            if ($i % 15 -eq 0) {
                $status.Text = "読み込み中… $i / $($files.Count)"
                [Windows.Forms.Application]::DoEvents()
            }
        }
        $lv.EndUpdate()
        $form.Cursor = 'Default'
        Update-Status
    }

    function Set-AllChecked([bool]$v) {
        $script:Bulk = $true
        $lv.BeginUpdate()
        foreach ($it in $lv.Items) { $it.Checked = $v }
        $lv.EndUpdate()
        $script:Bulk = $false
        Update-Status
    }

    # --- イベント
    $combo.Add_SelectedIndexChanged({ Load-List })
    $rbOlder.Add_CheckedChanged({ Load-List })
    $btnReload.Add_Click({ Load-List })
    $btnOpen.Add_Click({ if (Test-Path -LiteralPath $script:CurrentFolder) { Start-Process explorer.exe $script:CurrentFolder } })
    $btnChange.Add_Click({
        $dlg = New-Object Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'スクリーンショットのフォルダを選んでください'
        if (Test-Path -LiteralPath $script:CurrentFolder) { $dlg.SelectedPath = $script:CurrentFolder }
        if ($dlg.ShowDialog($form) -eq 'OK') {
            $script:CurrentFolder = $dlg.SelectedPath
            Save-ScreenshotFolder $script:CurrentFolder
            Load-List
        }
    })
    $btnAll.Add_Click({ Set-AllChecked $true })
    $btnNone.Add_Click({ Set-AllChecked $false })
    $lv.Add_ItemChecked({ if (-not $script:Bulk) { Update-Status } })
    $lv.Add_ItemActivate({   # ダブルクリック / Enter で画像を開く
        foreach ($it in $lv.SelectedItems) { Start-Process $it.Tag.FullName }
    })
    $form.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'F5') { Load-List }
        elseif ($e.Control -and $e.KeyCode -eq 'A') { Set-AllChecked $true; $e.Handled = $true }
        elseif ($e.KeyCode -eq 'Space' -and $lv.SelectedItems.Count -gt 0) {
            foreach ($it in $lv.SelectedItems) { $it.Checked = -not $it.Checked }; $e.Handled = $true
        }
    })

    $btnDel.Add_Click({
        $targets = @($lv.CheckedItems | ForEach-Object { $_.Tag })
        if ($targets.Count -eq 0) {
            [void][Windows.Forms.MessageBox]::Show($form, '削除するスクリーンショットにチェックを入れてください。', 'スクショ整理')
            return
        }
        $size = ($targets | Measure-Object Length -Sum).Sum
        $perm = $chkPerm.Checked
        $how  = if ($perm) { '完全に削除（元に戻せません）' } else { 'ごみ箱に移動' }
        $ans = [Windows.Forms.MessageBox]::Show($form,
            "$($targets.Count) 件（$(Format-Size $size)）を${how}します。よろしいですか？",
            'スクショ整理', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }

        $ok = 0; $ng = @()
        foreach ($f in $targets) {
            try { Remove-Shot $f.FullName $perm; $ok++ } catch { $ng += $f.Name }
        }
        Load-List
        $msg = "$ok 件を削除しました（$(Format-Size $size)）。"
        if (-not $perm) { $msg += "`n※ ごみ箱を空にすると容量が空きます。" }
        if ($ng.Count) { $msg += "`n`n削除できなかったもの:`n" + ($ng -join "`n") }
        [void][Windows.Forms.MessageBox]::Show($form, $msg, 'スクショ整理')
    })

    $form.Add_Shown({ Load-List })
    [void][Windows.Forms.Application]::Run($form)
}
catch {
    [void][Windows.Forms.MessageBox]::Show("エラーが発生しました:`n$($_.Exception.Message)", 'スクショ整理', 'OK', 'Error')
}
