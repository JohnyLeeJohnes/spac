# Vygeneruje assets/spac.ico a assets/spac.png. Spouštěj z kořene repozitáře:
#   powershell -ExecutionPolicy Bypass -File tools/make-icon.ps1
Add-Type -AssemblyName System.Drawing

$assets = Join-Path $PSScriptRoot '..\assets'
New-Item -ItemType Directory -Force $assets | Out-Null

# Předloha se kreslí ve 1024 px a pak zmenšuje, ať jsou hrany hladké i v 16 px.
$size = 1024
$s = $size / 256.0
$master = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($master)
$g.SmoothingMode = 'AntiAlias'
$g.PixelOffsetMode = 'HighQuality'

function Color($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

# Noční obloha: zaoblený čtverec
$d = 2 * 58 * $s
$sky = New-Object System.Drawing.Drawing2D.GraphicsPath
$sky.AddArc(0, 0, $d, $d, 180, 90)
$sky.AddArc($size - $d, 0, $d, $d, 270, 90)
$sky.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
$sky.AddArc(0, $size - $d, $d, $d, 90, 90)
$sky.CloseFigure()
$night = New-Object System.Drawing.Drawing2D.LinearGradientBrush `
    (New-Object System.Drawing.PointF 0, 0), (New-Object System.Drawing.PointF 0, $size), (Color '#222C4D'), (Color '#0B0F1C')
$g.FillPath($night, $sky)

# Srpek: žlutý kruh, do kterého se stejným štětcem oblohy "vykousne" druhý kruh
$moon = New-Object System.Drawing.SolidBrush (Color '#F4C95D')
$g.FillEllipse($moon, 54 * $s, 58 * $s, 148 * $s, 148 * $s)
$g.FillEllipse($night, 96 * $s, 36 * $s, 134 * $s, 134 * $s)

# Dvě hvězdy
$star = New-Object System.Drawing.SolidBrush (Color '#FBE9B7')
$g.FillEllipse($star, 160 * $s, 82 * $s, 15 * $s, 15 * $s)
$g.FillEllipse($star, 194 * $s, 118 * $s, 9 * $s, 9 * $s)
$g.Dispose()

function Resize([int]$px) {
    $bmp = New-Object System.Drawing.Bitmap $px, $px, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.InterpolationMode = 'HighQualityBicubic'
    $gr.PixelOffsetMode = 'HighQuality'
    $gr.DrawImage($master, 0, 0, $px, $px)
    $gr.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

$sizes = 256, 64, 48, 32, 24, 16
$frames = $sizes | ForEach-Object { , (Resize $_) }

# ICO = hlavička + adresář + PNG snímky za sebou
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter $out
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

[System.IO.File]::WriteAllBytes((Join-Path $assets 'spac.ico'), $out.ToArray())
[System.IO.File]::WriteAllBytes((Join-Path $assets 'spac.png'), $frames[0])
"Hotovo: assets/spac.ico, assets/spac.png"
