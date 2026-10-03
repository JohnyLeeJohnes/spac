# Vygeneruje assets/spac.ico a assets/spac.png:
#   powershell -ExecutionPolicy Bypass -File tools/make-icon.ps1
Add-Type -AssemblyName System.Drawing

$assets = Join-Path $PSScriptRoot '..\assets'
New-Item -ItemType Directory -Force $assets | Out-Null

function Color($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
function Point($x, $y) { New-Object System.Drawing.PointF $x, $y }

# Čtyřcípá hvězda s prohnutými stranami
function Sparkle($g, $brush, $cx, $cy, $r) {
    $c = $r * 0.16
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $tips = (Point $cx ($cy - $r)), (Point ($cx + $r) $cy), (Point $cx ($cy + $r)), (Point ($cx - $r) $cy)
    $bends = (Point ($cx + $c) ($cy - $c)), (Point ($cx + $c) ($cy + $c)), (Point ($cx - $c) ($cy + $c)), (Point ($cx - $c) ($cy - $c))
    for ($i = 0; $i -lt 4; $i++) {
        $path.AddBezier($tips[$i], $bends[$i], $bends[$i], $tips[($i + 1) % 4])
    }
    $path.CloseFigure()
    $g.FillPath($brush, $path)
}

# Každá velikost se kreslí zvlášť (4x větší a pak zmenšená), malé dostanou jednodušší kresbu.
function Draw([int]$px) {
    $size = $px * 4
    $s = $size / 256.0
    $small = $px -le 32

    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'

    # Noční obloha
    $d = 2 * 60 * $s
    $sky = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sky.AddArc(0, 0, $d, $d, 180, 90)
    $sky.AddArc($size - $d, 0, $d, $d, 270, 90)
    $sky.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
    $sky.AddArc(0, $size - $d, $d, $d, 90, 90)
    $sky.CloseFigure()
    $night = New-Object System.Drawing.Drawing2D.LinearGradientBrush (Point 0 0), (Point 0 $size), (Color '#2C3968'), (Color '#0B0F1E')
    $g.FillPath($night, $sky)

    # Srpek: kruh, do kterého se štětcem oblohy "vykousne" druhý kruh
    if ($small) { $m = 34, 42, 176; $cut = 86, 14, 158 } else { $m = 44, 60, 152; $cut = 88, 36, 138 }
    $gold = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
        (Point ($m[0] * $s) ($m[1] * $s)), (Point (($m[0] + $m[2]) * $s) (($m[1] + $m[2]) * $s)), (Color '#FFE9A6'), (Color '#EFB23E')
    $g.FillEllipse($gold, $m[0] * $s, $m[1] * $s, $m[2] * $s, $m[2] * $s)
    $g.FillEllipse($night, $cut[0] * $s, $cut[1] * $s, $cut[2] * $s, $cut[2] * $s)

    if (-not $small) {
        $star = New-Object System.Drawing.SolidBrush (Color '#FFF3CC')
        Sparkle $g $star (170 * $s) (92 * $s) (24 * $s)
        Sparkle $g $star (206 * $s) (140 * $s) (12 * $s)

        # Tenká světlá linka, ať má ikona hranu i na tmavém pozadí
        $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(36, 255, 255, 255)), (3 * $s)
        $edge.Alignment = 'Inset'
        $g.DrawPath($edge, $sky)
    }
    $g.Dispose()

    $out = New-Object System.Drawing.Bitmap $px, $px, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($bmp, 0, 0, $px, $px)
    $g.Dispose()
    $bmp.Dispose()

    $out
}

function Png($bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    , $ms.ToArray()
}

# Klasický snímek ICO: hlavička BITMAPINFOHEADER, pixely BGRA zdola nahoru, prázdná maska
function Dib($bmp) {
    $px = $bmp.Width
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter $ms
    $w.Write([uint32]40); $w.Write([int32]$px); $w.Write([int32]($px * 2))   # výška = obrázek + maska
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write((New-Object byte[] 24))

    $rect = New-Object System.Drawing.Rectangle 0, 0, $px, $px
    $data = $bmp.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $row = New-Object byte[] ($px * 4)
    for ($y = $px - 1; $y -ge 0; $y--) {
        [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride), $row, 0, $row.Length)
        $w.Write($row)
    }
    $bmp.UnlockBits($data)

    $maskStride = [int][Math]::Ceiling($px / 32.0) * 4
    $w.Write((New-Object byte[] ($maskStride * $px)))
    $w.Flush()
    , $ms.ToArray()
}

# 256 px jako PNG, menší jako BMP: tak to čtou i starší nástroje.
$sizes = 256, 64, 48, 40, 32, 24, 20, 16
$bitmaps = $sizes | ForEach-Object { Draw $_ }
$frames = $bitmaps | ForEach-Object { if ($_.Width -eq 256) { , (Png $_) } else { , (Dib $_) } }

# ICO = hlavička + adresář + PNG snímky za sebou
$ico = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $ico
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dim = [byte]($sizes[$i] % 256)   # 256 px se zapisuje jako 0
    $w.Write($dim); $w.Write($dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$frames[$i].Length); $w.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($frame in $frames) { $w.Write($frame) }
$w.Flush()

[System.IO.File]::WriteAllBytes((Join-Path $assets 'spac.ico'), $ico.ToArray())
[System.IO.File]::WriteAllBytes((Join-Path $assets 'spac.png'), (Png $bitmaps[0]))
"OK: assets/spac.ico ($($sizes -join ', ') px), assets/spac.png"
