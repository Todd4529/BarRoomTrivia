$ftpServer = $env:HOSTINGER_FTP_HOST
if (-not $ftpServer) { $ftpServer = "82.180.172.248" }

$ftpUser = $env:HOSTINGER_FTP_USER
if (-not $ftpUser) { $ftpUser = "u371548014.barroomstrivia.com" }

$ftpPass = $env:HOSTINGER_FTP_PASSWORD
if (-not $ftpPass) { 
    $ftpPass = "rSU+5^L&zL>2"
}
$sourceDir = (Resolve-Path ".\dist").Path

Write-Host "Starting deployment to Hostinger FTP ($ftpServer)..." -ForegroundColor Cyan

function Make-FtpDirectory {
    param ([string]$remotePath)
    try {
        $uri = "ftp://$ftpServer/$remotePath"
        $request = [System.Net.FtpWebRequest]::Create($uri)
        $request.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $request.UsePassive = $true
        $response = $request.GetResponse()
        $response.Close()
        Write-Host "Created remote directory: $remotePath" -ForegroundColor Green
    } catch {
        # Directory might already exist, ignore error
    }
}

function Upload-FtpFile {
    param (
        [string]$localFilePath,
        [string]$remoteFilePath
    )
    $uri = "ftp://$ftpServer/$remoteFilePath"
    $request = [System.Net.FtpWebRequest]::Create($uri)
    $request.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
    $request.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $request.UseBinary = $true
    $request.UsePassive = $true
    $request.KeepAlive = $false
    $request.Timeout = 30000

    $fileBytes = [System.IO.File]::ReadAllBytes($localFilePath)
    $request.ContentLength = $fileBytes.Length

    $requestStream = $request.GetRequestStream()
    $requestStream.Write($fileBytes, 0, $fileBytes.Length)
    $requestStream.Close()

    $response = $request.GetResponse()
    $response.Close()
    Write-Host "Uploaded: $remoteFilePath ($($fileBytes.Length) bytes)" -ForegroundColor Gray
}

# 1. Create required directories first
$allDirs = Get-ChildItem -Path $sourceDir -Recurse -Directory
# Sort by depth so parent directories are created first
$sortedDirs = $allDirs | Sort-Object { $_.FullName.Length }

foreach ($dir in $sortedDirs) {
    $relative = $dir.FullName.Substring($sourceDir.Length).TrimStart('\').Replace('\', '/')
    if ($relative) {
        Make-FtpDirectory -remotePath $relative
    }
}

# 2. Upload all files
$allFiles = Get-ChildItem -Path $sourceDir -Recurse -File

Write-Host "Uploading $($allFiles.Count) files..." -ForegroundColor Yellow

$uploadedCount = 0
foreach ($file in $allFiles) {
    $relative = $file.FullName.Substring($sourceDir.Length).TrimStart('\').Replace('\', '/')
    Upload-FtpFile -localFilePath $file.FullName -remoteFilePath $relative
    $uploadedCount++
}

Write-Host "`nDeployment completed successfully! Uploaded $uploadedCount files." -ForegroundColor Green
