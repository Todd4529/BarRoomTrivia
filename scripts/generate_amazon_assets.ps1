Add-Type -AssemblyName System.Drawing

$assetsDir = "amazon_store_assets"
if (-not (Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
}

$logoPath = "assets/images/app_logo.png"
$logoImg = [System.Drawing.Image]::FromFile($logoPath)

# Color palette matching Bar Rooms Trivia
$cDarkBg = [System.Drawing.Color]::FromArgb(255, 13, 15, 23)
$cCardBg = [System.Drawing.Color]::FromArgb(255, 26, 31, 46)
$cCardElevated = [System.Drawing.Color]::FromArgb(255, 34, 40, 60)
$cCyan = [System.Drawing.Color]::FromArgb(255, 0, 229, 255)
$cPink = [System.Drawing.Color]::FromArgb(255, 255, 46, 99)
$cYellow = [System.Drawing.Color]::FromArgb(255, 255, 230, 0)
$cGreen = [System.Drawing.Color]::FromArgb(255, 0, 230, 118)
$cWhite = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$cGray = [System.Drawing.Color]::FromArgb(255, 160, 174, 192)

$fHeader = New-Object System.Drawing.Font('Segoe UI', 36, [System.Drawing.FontStyle]::Bold)
$fSub = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Regular)
$fCardTitle = New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
$fCardBody = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Regular)
$fSmall = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)

# -------------------------------------------------------------
# 1. Fire TV Screenshot 1 (1920x1080) - Live Question & TV Mode
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1080)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$brushBg = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)), [System.Drawing.Color]::FromArgb(255, 10, 12, 18), [System.Drawing.Color]::FromArgb(255, 20, 25, 38), 45
$g.FillRectangle($brushBg, 0, 0, 1920, 1080)

$g.DrawImage($logoImg, 60, 40, 70, 70)
$brushCyan = New-Object System.Drawing.SolidBrush($cCyan)
$brushWhite = New-Object System.Drawing.SolidBrush($cWhite)
$brushYellow = New-Object System.Drawing.SolidBrush($cYellow)
$brushGray = New-Object System.Drawing.SolidBrush($cGray)
$g.DrawString('BAR ROOMS TRIVIA', $fHeader, $brushWhite, 150, 45)
$g.DrawString('ROUND 2 - QUESTION 4 OF 10 - SCIENCE AND TECHNOLOGY', $fSub, $brushCyan, 155, 95)

$penCyan = New-Object System.Drawing.Pen($cCyan, 3)
$brushElev = New-Object System.Drawing.SolidBrush($cCardElevated)
$g.FillRectangle($brushElev, 1600, 45, 260, 65)
$g.DrawRectangle($penCyan, 1600, 45, 260, 65)
$g.DrawString('TIME: 18s LEFT', (New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)), $brushYellow, 1625, 56)

$brushCard = New-Object System.Drawing.SolidBrush($cCardBg)
$penCard = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 45, 55, 80), 2)
$g.FillRectangle($brushCard, 60, 150, 1800, 360)
$g.DrawRectangle($penCard, 60, 150, 1800, 360)

$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 40, 20, 70))), 100, 185, 320, 40)
$g.DrawRectangle((New-Object System.Drawing.Pen($cPink, 2)), 100, 185, 320, 40)
$g.DrawString('SCIENCE AND TECHNOLOGY', $fSmall, (New-Object System.Drawing.SolidBrush($cPink)), 115, 193)

$qText = 'What chemical element has the atomic symbol Au on the periodic table?'
$g.DrawString($qText, (New-Object System.Drawing.Font('Segoe UI', 34, [System.Drawing.FontStyle]::Bold)), $brushWhite, (New-Object System.Drawing.RectangleF(100, 260, 1720, 200)))

$optColors = @($cCyan, $cPink, $cYellow, $cGreen)
$optLetters = @('A', 'B', 'C', 'D')
$optTexts = @('Gold', 'Silver', 'Argon', 'Platinum')
$coords = @(
    @{ X = 60; Y = 550 },
    @{ X = 980; Y = 550 },
    @{ X = 60; Y = 780 },
    @{ X = 980; Y = 780 }
)

for ($i = 0; $i -lt 4; $i++) {
    $c = $coords[$i]
    $clr = $optColors[$i]
    $g.FillRectangle($brushCard, $c.X, $c.Y, 880, 190)
    $g.DrawRectangle((New-Object System.Drawing.Pen($clr, 2.5)), $c.X, $c.Y, 880, 190)
    
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($clr)), ($c.X + 25), ($c.Y + 25), 65, 65)
    $g.DrawString($optLetters[$i], (New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)), ($c.X + 40), ($c.Y + 30))
    $g.DrawString($optTexts[$i], (New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)), $brushWhite, ($c.X + 115), ($c.Y + 35))
}

$g.FillRectangle($brushElev, 60, 995, 1800, 60)
$g.DrawString('JOIN ON YOUR PHONE: Visit barroomstrivia.com  |  Room Code: TRIV  |  Instant Live Scoring', $fSub, $brushWhite, 420, 1008)

$g.Dispose()
$bmp.Save("$assetsDir/fire_tv_screenshot_1.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created fire_tv_screenshot_1.png'

# -------------------------------------------------------------
# 2. Fire TV Screenshot 2 (1920x1080) - Live TV Leaderboard
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1080)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle($brushBg, 0, 0, 1920, 1080)

$g.DrawImage($logoImg, 60, 40, 70, 70)
$g.DrawString('BAR ROOMS TRIVIA', $fHeader, $brushWhite, 150, 45)
$g.DrawString('ROUND 2 COMPLETED - LIVE LEADERBOARD', $fSub, $brushYellow, 155, 95)

$podiums = @(
    @{ Name = 'TRIVIA KINGS'; Score = '140 PTS'; Badge = '1ST PLACE (+20 BONUS)'; X = 200; Y = 200; W = 460; H = 220; Color = $cYellow },
    @{ Name = 'BAR CRAWLERS'; Score = '120 PTS'; Badge = '2ND PLACE'; X = 730; Y = 230; W = 460; H = 190; Color = [System.Drawing.Color]::Silver },
    @{ Name = 'BEER GENIUSES'; Score = '100 PTS'; Badge = '3RD PLACE'; X = 1260; Y = 260; W = 460; H = 160; Color = [System.Drawing.Color]::FromArgb(255, 205, 127, 50) }
)

foreach ($p in $podiums) {
    $penP = New-Object System.Drawing.Pen($p.Color, 3)
    $g.FillRectangle($brushElev, $p.X, $p.Y, $p.W, $p.H)
    $g.DrawRectangle($penP, $p.X, $p.Y, $p.W, $p.H)
    $g.DrawString($p.Badge, $fCardTitle, (New-Object System.Drawing.SolidBrush($p.Color)), ($p.X + 30), ($p.Y + 25))
    $g.DrawString($p.Name, (New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)), $brushWhite, ($p.X + 30), ($p.Y + 80))
    $g.DrawString($p.Score, $fCardTitle, (New-Object System.Drawing.SolidBrush($cCyan)), ($p.X + 30), ($p.Y + 140))
}

$g.FillRectangle($brushCard, 200, 470, 1520, 470)
$g.DrawRectangle($penCard, 200, 470, 1520, 470)
$g.DrawString('FULL TABLE STANDINGS', $fCardTitle, $brushWhite, 240, 500)

$tablePlayers = @(
    @('4', 'PUB HEROES', '90 PTS', '7/10 Correct'),
    @('5', 'HOP HEADS', '80 PTS', '6/10 Correct'),
    @('6', 'THE SMART ALECS', '70 PTS', '5/10 Correct'),
    @('7', 'QUIZ PRO QUO', '60 PTS', '5/10 Correct'),
    @('8', 'LAST ORDERS', '50 PTS', '4/10 Correct')
)

$tY = 560
foreach ($row in $tablePlayers) {
    $g.DrawString($row[0], $fSub, $brushCyan, 250, $tY)
    $g.DrawString($row[1], $fSub, $brushWhite, 340, $tY)
    $g.DrawString($row[2], $fSub, $brushYellow, 1000, $tY)
    $g.DrawString($row[3], $fSub, $brushGray, 1350, $tY)
    $g.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 40, 48, 70), 1)), 240, ($tY + 45), 1680, ($tY + 45))
    $tY += 60
}

$g.FillRectangle($brushElev, 60, 995, 1800, 60)
$g.DrawString('NEXT ROUND STARTING IN 15 SECONDS - GET READY!', $fSub, $brushYellow, 620, 1008)

$g.Dispose()
$bmp.Save("$assetsDir/fire_tv_screenshot_2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created fire_tv_screenshot_2.png'

# -------------------------------------------------------------
# 3. Fire TV Screenshot 3 (1920x1080) - 30+ Genres Selection
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1080)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle($brushBg, 0, 0, 1920, 1080)

$g.DrawImage($logoImg, 60, 40, 70, 70)
$g.DrawString('BAR ROOMS TRIVIA', $fHeader, $brushWhite, 150, 45)
$g.DrawString('OVER 30 AUTHENTIC HUMAN-VERIFIED GENRES', $fSub, $brushCyan, 155, 95)

$genreSample = @(
    'Homebrewing Beer', 'Beer, Wine & Spirits', 'Food & Culinary', 'Movies & Hollywood',
    'Pop Culture & Music', 'Rock & Roll Classics', '80s & 90s Nostalgia', 'Sitcoms & TV Dramas',
    'Video Games & Gaming', 'Comics & Superheroes', 'Science & Technology', 'Mind Benders & Riddles',
    'Classic Literature', 'Art & Architecture', 'Sports & Stadiums', 'World History',
    'World Geography', 'Automotive & Racing', 'Wildlife & Nature', 'Mythology & Folklore',
    'Health & Medicine', 'Astronomy & Space', 'Home Repair', 'Finance & Markets'
)

$gx = 60
$gy = 170
$colW = 425
$rowH = 110

for ($i = 0; $i -lt $genreSample.Length; $i++) {
    $col = $i % 4
    $row = [Math]::Floor($i / 4)
    $x = $gx + ($col * 450)
    $y = $gy + ($row * 130)

    $g.FillRectangle($brushElev, $x, $y, $colW, $rowH)
    $g.DrawRectangle((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 50, 65, 95), 2)), $x, $y, $colW, $rowH)
    $g.DrawString($genreSample[$i], (New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)), $brushWhite, ($x + 20), ($y + 35))
}

$g.FillRectangle($brushCard, 60, 970, 1800, 80)
$g.DrawRectangle((New-Object System.Drawing.Pen($cCyan, 2)), 60, 970, 1800, 80)
$g.DrawString('100% Human-Crafted Questions - Zero Repetitions - Designed for TVs, Bars, & Game Nights', $fSub, $brushCyan, 340, 995)

$g.Dispose()
$bmp.Save("$assetsDir/fire_tv_screenshot_3.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created fire_tv_screenshot_3.png'

# -------------------------------------------------------------
# 4. Fire TV Background (1920x1080)
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1080)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)), [System.Drawing.Color]::FromArgb(255, 8, 10, 16), [System.Drawing.Color]::FromArgb(255, 18, 22, 35), 30
$g.FillRectangle($bgBrush, 0, 0, 1920, 1080)

$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 0, 229, 255))), 1300, -100, 800, 800)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 255, 46, 99))), -100, 500, 900, 900)
$g.DrawString('BAR ROOMS TRIVIA', (New-Object System.Drawing.Font('Segoe UI', 72, [System.Drawing.FontStyle]::Bold)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(18, 255, 255, 255))), 300, 460)

$g.Dispose()
$bmp.Save("$assetsDir/fire_tv_background_1920x1080.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created fire_tv_background_1920x1080.png'

# -------------------------------------------------------------
# 5. Featured Content Logo (640x260 Transparent PNG)
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(640, 260)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$g.DrawImage($logoImg, 30, 45, 170, 170)
$g.DrawString('BAR ROOMS', (New-Object System.Drawing.Font('Segoe UI', 36, [System.Drawing.FontStyle]::Bold)), $brushWhite, 230, 60)
$g.DrawString('TRIVIA', (New-Object System.Drawing.Font('Segoe UI', 48, [System.Drawing.FontStyle]::Bold)), $brushCyan, 230, 115)

$g.Dispose()
$bmp.Save("$assetsDir/featured_content_logo.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created featured_content_logo.png'

# -------------------------------------------------------------
# 6. Featured Content Background (1920x1080)
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1080)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$featBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)), [System.Drawing.Color]::FromArgb(255, 12, 14, 24), [System.Drawing.Color]::FromArgb(255, 24, 30, 50), 60
$g.FillRectangle($featBrush, 0, 0, 1920, 1080)

$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 0, 229, 255))), 1200, 200, 700, 700)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 255, 230, 0))), 200, -200, 800, 800)

$g.Dispose()
$bmp.Save("$assetsDir/featured_content_background.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created featured_content_background.png'

# -------------------------------------------------------------
# 7. Tablet Screenshot 1 (1920x1200) - Player Controller Screen
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1200)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle($brushBg, 0, 0, 1920, 1200)

$g.FillRectangle($brushElev, 260, 40, 1400, 110)
$g.DrawRectangle((New-Object System.Drawing.Pen($cCyan, 2)), 260, 40, 1400, 110)
$g.DrawImage($logoImg, 290, 55, 80, 80)
$g.DrawString('TRIVIA CHAMPION', (New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)), $brushCyan, 400, 55)
$g.DrawString('ROOM: TRIV - ROUND 1 - QUESTION 3 OF 10', $fSub, $brushGray, 400, 100)
$g.DrawString('TIME: 14s', (New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)), $brushYellow, 1220, 70)
$g.DrawString('80 PTS', (New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)), $brushCyan, 1480, 70)

$g.FillRectangle($brushCard, 260, 190, 1400, 320)
$g.DrawRectangle($penCard, 260, 190, 1400, 320)
$g.DrawString('MOVIES AND HOLLYWOOD', $fSmall, (New-Object System.Drawing.SolidBrush($cPink)), 300, 220)
$g.DrawString('Who directed the 1993 Academy Award-winning blockbuster Jurassic Park?', (New-Object System.Drawing.Font('Segoe UI', 32, [System.Drawing.FontStyle]::Bold)), $brushWhite, (New-Object System.Drawing.RectangleF(300, 270, 1320, 200)))

$tabletOptions = @('Steven Spielberg', 'James Cameron', 'George Lucas', 'Ridley Scott')
$tCoords = @(
    @{ X = 260; Y = 550 },
    @{ X = 980; Y = 550 },
    @{ X = 260; Y = 840 },
    @{ X = 980; Y = 840 }
)

for ($i = 0; $i -lt 4; $i++) {
    $c = $tCoords[$i]
    $clr = $optColors[$i]
    $g.FillRectangle($brushElev, $c.X, $c.Y, 680, 250)
    $g.DrawRectangle((New-Object System.Drawing.Pen($clr, 3)), $c.X, $c.Y, 680, 250)
    
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($clr)), ($c.X + 35), ($c.Y + 35), 75, 75)
    $g.DrawString($optLetters[$i], (New-Object System.Drawing.Font('Segoe UI', 32, [System.Drawing.FontStyle]::Bold)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)), ($c.X + 55), ($c.Y + 45))
    $g.DrawString($tabletOptions[$i], (New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)), $brushWhite, ($c.X + 135), ($c.Y + 50))
}

$g.Dispose()
$bmp.Save("$assetsDir/tablet_screenshot_1.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created tablet_screenshot_1.png'

# -------------------------------------------------------------
# 8. Tablet Screenshot 2 (1920x1200) - Host Dashboard View
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1200)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle($brushBg, 0, 0, 1920, 1200)

$g.DrawImage($logoImg, 60, 40, 70, 70)
$g.DrawString('HOST CONTROL DASHBOARD', $fHeader, $brushWhite, 150, 45)
$g.DrawString('ACTIVE SESSION: ROOM TRIV - 14 CONNECTED PLAYERS', $fSub, $brushCyan, 155, 95)

$g.FillRectangle($brushElev, 60, 160, 560, 450)
$g.DrawRectangle((New-Object System.Drawing.Pen($cCyan, 2)), 60, 160, 560, 450)
$g.DrawString('GAME STATUS', $fCardTitle, $brushWhite, 90, 190)
$g.DrawString('STATUS: IN PROGRESS', $fSub, $brushGreen, 90, 250)
$g.DrawString('CURRENT ROUND: 2', $fSub, $brushWhite, 90, 295)
$g.DrawString('QUESTION: 4 OF 10', $fSub, $brushWhite, 90, 340)
$g.DrawString('TIMER: AUTO (20s)', $fSub, $brushYellow, 90, 385)

$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 230, 81, 0))), 90, 460, 230, 70)
$g.DrawString('PAUSE', (New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)), $brushWhite, 160, 480)

$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0, 150, 136))), 350, 460, 230, 70)
$g.DrawString('NEXT Q', (New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)), $brushWhite, 415, 480)

$g.FillRectangle($brushCard, 660, 160, 1200, 450)
$g.DrawRectangle($penCard, 660, 160, 1200, 450)
$g.DrawString('ORDERED GENRE PLAYLIST ROTATION', $fCardTitle, $brushWhite, 700, 190)

$pGenres = @('Round 1: Homebrewing Beer', 'Round 2: Science and Technology (ACTIVE)', 'Round 3: Movies and Hollywood', 'Round 4: Rock and Roll Classics', 'Round 5: Food and Culinary')
$pY = 250
foreach ($pg in $pGenres) {
    $g.DrawString($pg, (New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Regular)), $brushWhite, 700, $pY)
    $pY += 55
}

$g.FillRectangle($brushCard, 60, 650, 1800, 480)
$g.DrawRectangle($penCard, 60, 650, 1800, 480)
$g.DrawString('CONNECTED PLAYERS (14 TOTAL)', $fCardTitle, $brushWhite, 100, 680)

$players = @(
    @('TRIVIA KINGS', '140 PTS', 'Ready', 'Round 1 Winner'),
    @('BAR CRAWLERS', '120 PTS', 'Answering', 'Online'),
    @('BEER GENIUSES', '100 PTS', 'Answering', 'Online'),
    @('PUB HEROES', '90 PTS', 'Ready', 'Online'),
    @('HOP HEADS', '80 PTS', 'Ready', 'Online')
)

$plY = 740
foreach ($pl in $players) {
    $g.DrawString($pl[0], $fSub, $brushCyan, 120, $plY)
    $g.DrawString($pl[1], $fSub, $brushYellow, 600, $plY)
    $g.DrawString($pl[2], $fSub, $brushGreen, 1000, $plY)
    $g.DrawString($pl[3], $fSub, $brushGray, 1400, $plY)
    $g.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 45, 55, 80), 1)), 100, ($plY + 45), 1800, ($plY + 45))
    $plY += 65
}

$g.Dispose()
$bmp.Save("$assetsDir/tablet_screenshot_2.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created tablet_screenshot_2.png'

# -------------------------------------------------------------
# 9. Tablet Screenshot 3 (1920x1200) - Round Winners & Transition
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1920, 1200)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.FillRectangle($brushBg, 0, 0, 1920, 1200)

$g.FillRectangle($brushCard, 360, 180, 1200, 840)
$g.DrawRectangle((New-Object System.Drawing.Pen($cYellow, 4)), 360, 180, 1200, 840)

$g.DrawString('ROUND COMPLETED!', (New-Object System.Drawing.Font('Segoe UI', 44, [System.Drawing.FontStyle]::Bold)), $brushYellow, 560, 230)
$g.DrawString('ROUND 2 WINNERS AND BONUS POINTS', $fSub, $brushWhite, 680, 310)

$wY = 380
$winRows = @(
    @('1ST PLACE (+20 BONUS)', 'TRIVIA KINGS', '140 PTS', $cYellow),
    @('2ND PLACE', 'BAR CRAWLERS', '120 PTS', [System.Drawing.Color]::Silver),
    @('3RD PLACE', 'BEER GENIUSES', '100 PTS', [System.Drawing.Color]::FromArgb(255, 205, 127, 50))
)

foreach ($wr in $winRows) {
    $g.FillRectangle($brushElev, 440, $wY, 1040, 110)
    $g.DrawRectangle((New-Object System.Drawing.Pen($wr[3], 2)), 440, $wY, 1040, 110)
    $g.DrawString($wr[0], $fCardTitle, (New-Object System.Drawing.SolidBrush($wr[3])), 480, ($wY + 15))
    $g.DrawString($wr[1], (New-Object System.Drawing.Font('Segoe UI', 28, [System.Drawing.FontStyle]::Bold)), $brushWhite, 480, ($wY + 55))
    $g.DrawString($wr[2], (New-Object System.Drawing.Font('Segoe UI', 32, [System.Drawing.FontStyle]::Bold)), (New-Object System.Drawing.SolidBrush($cCyan)), 1250, ($wY + 30))
    $wY += 130
}

$g.FillRectangle([System.Drawing.Color]::FromArgb(255, 10, 14, 24), 440, 800, 1040, 160)
$g.DrawRectangle((New-Object System.Drawing.Pen($cCyan, 2)), 440, 800, 1040, 160)
$g.DrawString('NEXT ROUND STARTS IN', $fCardTitle, $brushYellow, 760, 825)
$g.DrawString('0:15', (New-Object System.Drawing.Font('Segoe UI', 48, [System.Drawing.FontStyle]::Bold)), $brushWhite, 880, 870)

$g.Dispose()
$bmp.Save("$assetsDir/tablet_screenshot_3.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created tablet_screenshot_3.png'

# -------------------------------------------------------------
# 10. Promotional Image (1024x500)
# -------------------------------------------------------------
$bmp = New-Object System.Drawing.Bitmap(1024, 500)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$promoBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle(0, 0, 1024, 500)), [System.Drawing.Color]::FromArgb(255, 10, 12, 22), [System.Drawing.Color]::FromArgb(255, 25, 30, 52), 45
$g.FillRectangle($promoBrush, 0, 0, 1024, 500)

$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35, 0, 229, 255))), 650, -50, 450, 450)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, 255, 46, 99))), -50, 200, 450, 450)

$g.DrawImage($logoImg, 60, 80, 180, 180)

$g.DrawString('BAR ROOMS TRIVIA', (New-Object System.Drawing.Font('Segoe UI', 38, [System.Drawing.FontStyle]::Bold)), $brushWhite, 270, 90)
$g.DrawString('Real-Time Multiplayer Trivia for Fire TV and Tablets', (New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)), $brushCyan, 275, 160)
$g.DrawString('30+ Human-Crafted Genres  |  Zero AI Filler  |  Instant QR Join', (New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Regular)), $brushWhite, 275, 205)

$badges = @('TV DISPLAY MODE', 'SMARTPHONE PLAYERS', 'REAL-TIME LEADERBOARD', 'BAR AND HOME GAMES')
$bx = 60
foreach ($b in $badges) {
    $g.FillRectangle($brushElev, $bx, 380, 215, 65)
    $g.DrawRectangle((New-Object System.Drawing.Pen($cCyan, 2)), $bx, 380, 215, 65)
    $g.DrawString($b, (New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)), $brushWhite, ($bx + 16), 405)
    $bx += 235
}

$g.Dispose()
$bmp.Save("$assetsDir/promotional_image_1024x500.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host 'Created promotional_image_1024x500.png'

$logoImg.Dispose()
Write-Host 'All Amazon Appstore assets generated successfully!'
