<#
.SYNOPSIS
    AlgerMusicPlayer WinUI 3 官方主题仓库一键上架/更新脚本
.DESCRIPTION
    扫描 inbox/ 目录中的 .algertheme.json / .json 主题导出包，自动提取内嵌 Base64 壁纸或同目录图片/视频壁纸到 wallpapers/，
    生成标准化主题归档 themes/<Id>.algertheme.json，更新根目录 index.json 清单（同 Id 原地更新，新主题置顶），
    清理已处理的 inbox 源文件，并自动提交推送到 GitHub。
    完全兼容简体中文 Windows 环境与中文路径/文件名。
#>
param(
    [string]$Category = "",
    [string]$Author = "",
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InboxDir = Join-Path $RepoRoot "inbox"
$ThemesDir = Join-Path $RepoRoot "themes"
$WallpapersDir = Join-Path $RepoRoot "wallpapers"
$PreviewsDir = Join-Path $RepoRoot "previews"
$IndexPath = Join-Path $RepoRoot "index.json"

New-Item -ItemType Directory -Path $InboxDir, $ThemesDir, $WallpapersDir, $PreviewsDir -Force | Out-Null

# 刷新 PATH，确保从资源管理器双击 bat 时也能找到 git
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath;$env:Path"

function Write-Utf8File {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Read-Utf8File {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-ThemeBaseName {
    param([string]$FilePath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    if ($name.EndsWith(".algertheme", [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = $name.Substring(0, $name.Length - ".algertheme".Length)
    }
    return $name
}

function Get-StableAsciiThemeId {
    param(
        $ThemeObj,
        [string]$BaseName
    )
    if (-not [string]::IsNullOrWhiteSpace($ThemeObj.MarketOriginId)) {
        $cand = ($ThemeObj.MarketOriginId.Trim() -replace '[^a-zA-Z0-9\-_]', '')
        if (-not [string]::IsNullOrWhiteSpace($cand)) { return $cand }
    }
    if (-not [string]::IsNullOrWhiteSpace($ThemeObj.Id) -and
        $ThemeObj.Id.StartsWith("repo-", [System.StringComparison]::OrdinalIgnoreCase)) {
        $cand = ($ThemeObj.Id.Trim() -replace '[^a-zA-Z0-9\-_]', '')
        if (-not [string]::IsNullOrWhiteSpace($cand)) { return $cand }
    }

    # 从文件名提取可读 ASCII 标识；全中文名称则附加确定性 8 位哈希保证唯一且稳定可覆盖更新
    $slug = ($BaseName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $seed = if (-not [string]::IsNullOrWhiteSpace($ThemeObj.Name)) { "$($ThemeObj.Name)|$($ThemeObj.Author)" } else { $BaseName }
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hashBytes = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
        $hashHex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant().Substring(0, 8)
    }
    finally {
        $sha1.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($slug)) {
        if ($slug.StartsWith("repo-")) { return $slug }
        return "repo-$slug"
    }
    return "repo-$hashHex"
}

function Ensure-NoteProperty {
    param($Obj, [string]$Name, $Value)
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $prop.Value = $Value
    }
}

function Resolve-AutoCategoryAndTags {
    param(
        $ThemeObj,
        [string]$WallpaperUrl,
        [string]$VideoUrl,
        [string]$ManualCategory
    )
    $backdrop = "$($ThemeObj.BackdropType)"
    $isLight = "$($ThemeObj.BaseMode)".Equals("Light", [System.StringComparison]::OrdinalIgnoreCase)
    $hasParticles = ($ThemeObj.EnableParticleOverlay -eq $true)
    $hasAudio = ($ThemeObj.EnableAudioReactive -eq $true)
    $hasPointer = ($ThemeObj.EnablePointerInteraction -eq $true)
    $audioStyle = "$($ThemeObj.AudioReactiveStyle)"
    $hasVideo = (-not [string]::IsNullOrWhiteSpace($VideoUrl)) -or $backdrop.Equals("Video", [System.StringComparison]::OrdinalIgnoreCase)
    $hasWallpaper = (-not [string]::IsNullOrWhiteSpace($WallpaperUrl)) -or $backdrop.Equals("Image", [System.StringComparison]::OrdinalIgnoreCase)

    $cat = $ManualCategory
    if ([string]::IsNullOrWhiteSpace($cat)) {
        if ($hasAudio -or $hasPointer) {
            $cat = "音频交互"
        }
        elseif ($hasWallpaper) {
            $cat = "光学壁纸"
        }
        elseif ($hasVideo -or $backdrop.Equals("Aurora", [System.StringComparison]::OrdinalIgnoreCase) -or $backdrop.Equals("CoverFlow", [System.StringComparison]::OrdinalIgnoreCase)) {
            $cat = "动态极光"
        }
        elseif ($hasParticles) {
            $cat = "粒子氛围"
        }
        elseif ($isLight) {
            $cat = "极简浅色"
        }
        else {
            $cat = "精选推荐"
        }
    }

    $tags = New-Object System.Collections.Generic.List[string]
    if ($hasAudio) {
        $tags.Add("音频交互")
        if ($audioStyle.Equals("PulseRings", [System.StringComparison]::OrdinalIgnoreCase)) { $tags.Add("脉冲声环") }
        elseif ($audioStyle.Equals("SilkWave", [System.StringComparison]::OrdinalIgnoreCase)) { $tags.Add("丝绸声波") }
        else { $tags.Add("镜像频谱") }
    }
    if ($hasPointer) { $tags.Add("指针交互") }
    if ($hasWallpaper) {
        $tags.Add("光学壁纸")
        if ("$($ThemeObj.CardVisualStyle)".Equals("LiquidGlass", [System.StringComparison]::OrdinalIgnoreCase)) {
            $tags.Add("液态折射")
        }
    }
    if ($hasVideo) { $tags.Add("动态视频") }
    if ($backdrop.Equals("Aurora", [System.StringComparison]::OrdinalIgnoreCase)) { $tags.Add("动态极光") }
    if ($backdrop.Equals("CoverFlow", [System.StringComparison]::OrdinalIgnoreCase)) { $tags.Add("随歌流光") }
    if ($hasParticles -and -not [string]::IsNullOrWhiteSpace("$($ThemeObj.ParticleType)")) {
        $tags.Add("$($ThemeObj.ParticleType)")
    }
    if ("$($ThemeObj.PlayBarLayoutMode)".Equals("FloatingIsland", [System.StringComparison]::OrdinalIgnoreCase)) {
        $tags.Add("悬浮岛")
    }
    $tags.Add($(if ($isLight) { "浅色" } else { "深色" }))

    return @{
        Category = $cat
        Tags = @($tags | Select-Object -Unique)
    }
}

$jsonFiles = @(Get-ChildItem -LiteralPath $InboxDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
if ($jsonFiles.Count -eq 0) {
    Write-Host "[提示] inbox 目录内未找到待上架的 .algertheme.json / .json 主题文件。" -ForegroundColor Yellow
    Write-Host "请先在客户端导出主题包 (.algertheme.json) 放入：$InboxDir" -ForegroundColor Cyan
    exit 0
}

# 读取或初始化 index.json
if (Test-Path -LiteralPath $IndexPath) {
    $manifest = (Read-Utf8File -Path $IndexPath) | ConvertFrom-Json
}
else {
    $manifest = [PSCustomObject]@{
        FeedName = "Alger 官方主题仓库"
        Items = @()
    }
}

$itemList = New-Object System.Collections.Generic.List[object]
if ($null -ne $manifest.Items) {
    foreach ($existingItem in $manifest.Items) {
        $itemList.Add($existingItem)
    }
}

$publishedNames = New-Object System.Collections.Generic.List[string]
$filesToClean = New-Object System.Collections.Generic.List[string]

$imageExts = @(".png", ".jpg", ".jpeg", ".webp", ".bmp")
$videoExts = @(".mp4", ".webm", ".mkv")

foreach ($jf in $jsonFiles) {
    Write-Host "正在处理主题包：$($jf.Name) ..." -ForegroundColor Cyan
    $rawJson = Read-Utf8File -Path $jf.FullName
    $themeObj = $rawJson | ConvertFrom-Json
    if ($null -eq $themeObj -or [string]::IsNullOrWhiteSpace("$($themeObj.Name)")) {
        Write-Host "  [跳过] 文件缺少有效 Theme.Name 字段：$($jf.Name)" -ForegroundColor Yellow
        continue
    }

    $baseName = Get-ThemeBaseName -FilePath $jf.FullName
    $themeId = Get-StableAsciiThemeId -ThemeObj $themeObj -BaseName $baseName
    Ensure-NoteProperty -Obj $themeObj -Name "Id" -Value $themeId
    Ensure-NoteProperty -Obj $themeObj -Name "MarketOriginId" -Value $themeId
    Ensure-NoteProperty -Obj $themeObj -Name "IsBuiltIn" -Value $false
    if (-not [string]::IsNullOrWhiteSpace($Author)) {
        Ensure-NoteProperty -Obj $themeObj -Name "Author" -Value $Author
    }
    elseif ([string]::IsNullOrWhiteSpace("$($themeObj.Author)")) {
        Ensure-NoteProperty -Obj $themeObj -Name "Author" -Value "TencenTiM"
    }

    $wallpaperRelUrl = ""
    $videoRelUrl = ""
    $previewRelUrl = ""

    # 1. 优先解析内嵌 Base64 图片并分离至 wallpapers/
    $b64 = "$($themeObj.EmbeddedImageBase64)"
    if (-not [string]::IsNullOrWhiteSpace($b64)) {
        $ext = "$($themeObj.EmbeddedImageExt)"
        if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".png" }
        if (-not $ext.StartsWith(".")) { $ext = "." + $ext }
        $ext = $ext.ToLowerInvariant()

        $destWallName = "$themeId$ext"
        $destWallPath = Join-Path $WallpapersDir $destWallName
        $imgBytes = [Convert]::FromBase64String($b64)
        [System.IO.File]::WriteAllBytes($destWallPath, $imgBytes)

        $wallpaperRelUrl = "wallpapers/$destWallName"
        Ensure-NoteProperty -Obj $themeObj -Name "BackdropType" -Value "Image"
        Ensure-NoteProperty -Obj $themeObj -Name "BackgroundImagePath" -Value ""
        Ensure-NoteProperty -Obj $themeObj -Name "EmbeddedImageBase64" -Value $null
        Ensure-NoteProperty -Obj $themeObj -Name "EmbeddedImageExt" -Value $null
        Write-Host "  -> 已从 Base64 拆出壁纸：$wallpaperRelUrl ($([Math]::Round($imgBytes.Length / 1KB, 1)) KB)" -ForegroundColor Green
    }

    # 2. 检查 inbox 同名壁纸图片（优先级高于本机绝对路径）
    if ([string]::IsNullOrWhiteSpace($wallpaperRelUrl)) {
        foreach ($ie in $imageExts) {
            $candImg = Join-Path $InboxDir "$baseName$ie"
            if (Test-Path -LiteralPath $candImg) {
                $destWallName = "$themeId$ie"
                Copy-Item -LiteralPath $candImg -Destination (Join-Path $WallpapersDir $destWallName) -Force
                $wallpaperRelUrl = "wallpapers/$destWallName"
                $filesToClean.Add($candImg)
                Ensure-NoteProperty -Obj $themeObj -Name "BackdropType" -Value "Image"
                Ensure-NoteProperty -Obj $themeObj -Name "BackgroundImagePath" -Value ""
                Write-Host "  -> 已归档同名壁纸图片：$wallpaperRelUrl" -ForegroundColor Green
                break
            }
        }
    }

    # 3. 检查 Theme.BackgroundImagePath 本机路径或相对仓库路径
    if ([string]::IsNullOrWhiteSpace($wallpaperRelUrl)) {
        $origImgPath = "$($themeObj.BackgroundImagePath)".Trim()
        if (-not [string]::IsNullOrWhiteSpace($origImgPath)) {
            if ($origImgPath.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
                $wallpaperRelUrl = $origImgPath
                Ensure-NoteProperty -Obj $themeObj -Name "BackgroundImagePath" -Value ""
            }
            elseif (Test-Path -LiteralPath $origImgPath) {
                $ie = [System.IO.Path]::GetExtension($origImgPath).ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($ie)) { $ie = ".jpg" }
                $destWallName = "$themeId$ie"
                Copy-Item -LiteralPath $origImgPath -Destination (Join-Path $WallpapersDir $destWallName) -Force
                $wallpaperRelUrl = "wallpapers/$destWallName"
                Ensure-NoteProperty -Obj $themeObj -Name "BackdropType" -Value "Image"
                Ensure-NoteProperty -Obj $themeObj -Name "BackgroundImagePath" -Value ""
                Write-Host "  -> 已复制本地壁纸至仓库：$wallpaperRelUrl" -ForegroundColor Green
            }
            else {
                $repoRelImg = Join-Path $RepoRoot ($origImgPath -replace '/', '\')
                if (Test-Path -LiteralPath $repoRelImg) {
                    $wallpaperRelUrl = ($origImgPath -replace '\\', '/')
                    Ensure-NoteProperty -Obj $themeObj -Name "BackgroundImagePath" -Value ""
                }
            }
        }
    }

    # 4. 检查 inbox 同名动态视频或 Theme.BackgroundVideoPath
    foreach ($ve in $videoExts) {
        $candVid = Join-Path $InboxDir "$baseName$ve"
        if (Test-Path -LiteralPath $candVid) {
            $destVidName = "$themeId$ve"
            Copy-Item -LiteralPath $candVid -Destination (Join-Path $WallpapersDir $destVidName) -Force
            $videoRelUrl = "wallpapers/$destVidName"
            $filesToClean.Add($candVid)
            Ensure-NoteProperty -Obj $themeObj -Name "BackdropType" -Value "Video"
            Ensure-NoteProperty -Obj $themeObj -Name "BackgroundVideoPath" -Value ""
            Write-Host "  -> 已归档同名动态视频：$videoRelUrl" -ForegroundColor Green
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($videoRelUrl)) {
        $origVidPath = "$($themeObj.BackgroundVideoPath)".Trim()
        if (-not [string]::IsNullOrWhiteSpace($origVidPath)) {
            if ($origVidPath.StartsWith("http", [System.StringComparison]::OrdinalIgnoreCase)) {
                $videoRelUrl = $origVidPath
                Ensure-NoteProperty -Obj $themeObj -Name "BackgroundVideoPath" -Value ""
            }
            elseif (Test-Path -LiteralPath $origVidPath) {
                $ve = [System.IO.Path]::GetExtension($origVidPath).ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($ve)) { $ve = ".mp4" }
                $destVidName = "$themeId$ve"
                Copy-Item -LiteralPath $origVidPath -Destination (Join-Path $WallpapersDir $destVidName) -Force
                $videoRelUrl = "wallpapers/$destVidName"
                Ensure-NoteProperty -Obj $themeObj -Name "BackdropType" -Value "Video"
                Ensure-NoteProperty -Obj $themeObj -Name "BackgroundVideoPath" -Value ""
                Write-Host "  -> 已复制本地视频至仓库：$videoRelUrl" -ForegroundColor Green
            }
        }
    }

    # 5. 检查可选预览截图 (<同名>.preview.jpg / .png)
    foreach ($pe in @(".jpg", ".jpeg", ".png", ".webp")) {
        $candPrev = Join-Path $InboxDir "$baseName.preview$pe"
        if (Test-Path -LiteralPath $candPrev) {
            $destPrevName = "$themeId$pe"
            Copy-Item -LiteralPath $candPrev -Destination (Join-Path $PreviewsDir $destPrevName) -Force
            $previewRelUrl = "previews/$destPrevName"
            $filesToClean.Add($candPrev)
            Write-Host "  -> 已归档自定义预览图：$previewRelUrl" -ForegroundColor Green
            break
        }
    }

    # 清除内嵌大字段后写入干净主题单文件 themes/<Id>.algertheme.json
    $themeObj.PSObject.Properties.Remove("EmbeddedImageBase64")
    $themeObj.PSObject.Properties.Remove("EmbeddedImageExt")
    $archiveThemePath = Join-Path $ThemesDir "$themeId.algertheme.json"
    Write-Utf8File -Path $archiveThemePath -Text ($themeObj | ConvertTo-Json -Depth 12)

    $meta = Resolve-AutoCategoryAndTags -ThemeObj $themeObj -WallpaperUrl $wallpaperRelUrl -VideoUrl $videoRelUrl -ManualCategory $Category

    # 查找是否已存在同 Id 条目
    $existingIdx = -1
    $prevDownloads = 100
    for ($idx = 0; $idx -lt $itemList.Count; $idx++) {
        if ("$($itemList[$idx].Id)".Equals($themeId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $existingIdx = $idx
            if ($null -ne $itemList[$idx].Downloads) {
                $prevDownloads = [int]$itemList[$idx].Downloads
            }
            break
        }
    }

    $marketEntry = [PSCustomObject]@{
        Id = $themeId
        Category = $meta.Category
        Tags = $meta.Tags
        Downloads = $prevDownloads
        SourceName = "官方主题仓库"
        PreviewImageUrl = $previewRelUrl
        WallpaperUrl = $wallpaperRelUrl
        VideoUrl = $videoRelUrl
        Theme = $themeObj
    }

    if ($existingIdx -ge 0) {
        $itemList[$existingIdx] = $marketEntry
        Write-Host "  -> 已更新现有主题条目：$($themeObj.Name) ($themeId)" -ForegroundColor Green
    }
    else {
        $itemList.Insert(0, $marketEntry)
        Write-Host "  -> 已新增上架主题条目：$($themeObj.Name) ($themeId)" -ForegroundColor Green
    }

    $publishedNames.Add("$($themeObj.Name)")
    $filesToClean.Add($jf.FullName)
}

if ($publishedNames.Count -eq 0) {
    Write-Host "[完成] 没有可上架的有效主题文件。" -ForegroundColor Yellow
    exit 0
}

# 更新 index.json
$feedNameValue = if ([string]::IsNullOrWhiteSpace("$($manifest.FeedName)")) { "Alger 官方主题仓库" } else { "$($manifest.FeedName)" }
$newManifest = [PSCustomObject]@{
    FeedName = $feedNameValue
    Items = $itemList.ToArray()
}
Write-Utf8File -Path $IndexPath -Text ($newManifest | ConvertTo-Json -Depth 16)

# 清理 inbox 中已归档的文件
foreach ($cf in $filesToClean) {
    if (Test-Path -LiteralPath $cf) {
        Remove-Item -LiteralPath $cf -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n[清单已更新] 当前仓库共收录 $($itemList.Count) 款在线主题：$IndexPath" -ForegroundColor Cyan

if ($NoPush) {
    Write-Host "[跳过推送] 已指定 -NoPush，请手动检查后推送到 GitHub。" -ForegroundColor Yellow
    exit 0
}

# 自动 Git 提交并推送到 GitHub
Set-Location $RepoRoot
$summary = ($publishedNames -join "、")
$commitMsg = "feat(theme): 发布/更新主题 ($summary)"

git add -A
$status = git status --porcelain
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "[提示] 仓库内容无变更，无需重复提交推送。" -ForegroundColor Yellow
    exit 0
}

git commit -m $commitMsg
if ($LASTEXITCODE -ne 0) {
    throw "git commit 执行失败！"
}

git push -u origin main
if ($LASTEXITCODE -ne 0) {
    throw "git push 执行失败，请检查网络连接或 GitHub 凭证。"
}

Write-Host "`n[发布成功] 已推送至 GitHub 主题仓库！客户端点击「刷新主题仓库」即可获取更新。" -ForegroundColor Green
