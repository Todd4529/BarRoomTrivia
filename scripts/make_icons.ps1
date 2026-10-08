Add-Type -AssemblyName System.Drawing

function Resize-ImageFile {
    param(
        [string]$sourcePath,
        [string]$destPath,
        [int]$width,
        [int]$height,
        [bool]$keepAlpha = $true
    )

    $src = [System.Drawing.Image]::FromFile($sourcePath)
    $destBmp = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($destBmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $g.DrawImage($src, $rect)
    $g.Dispose()
    $src.Dispose()

    $destBmp.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $destBmp.Dispose()
    Write-Host "Saved: $destPath ($width x $height)"
}

Resize-ImageFile "assets/images/app_logo.png" "amazon_store_assets/app_icon_512x512.png" 512 512
Resize-ImageFile "assets/images/app_logo.png" "amazon_store_assets/app_icon_114x114.png" 114 114
