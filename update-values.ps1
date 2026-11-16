#requires -Version 5.1
<#
    update-values.ps1
    -----------------
    Scrapes https://amvgg.com/values/* and regenerates:
      values/pets.json     - full dataset (name, value, demand, category, slug)
      values/values.lua    - compact Lua table used by the bot
    and injects the compact table into AdoptMeTradeBot.lua between the
    VALUES_BEGIN / VALUES_END markers.

    Usage:
        powershell -ExecutionPolicy Bypass -File tools\update-values.ps1
#>

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Culture = [System.Globalization.CultureInfo]::InvariantCulture

# category code -> page.  The numeric id is what gets baked into the Lua table.
$Categories = @(
    [pscustomobject]@{ Code = 'pet';     Page = 'pets';     Id = 1 },
    [pscustomobject]@{ Code = 'egg';     Page = 'eggs';     Id = 2 },
    [pscustomobject]@{ Code = 'petwear'; Page = 'petwear';  Id = 3 },
    [pscustomobject]@{ Code = 'stroller';Page = 'strollers';Id = 4 },
    [pscustomobject]@{ Code = 'vehicle'; Page = 'vehicles'; Id = 5 },
    [pscustomobject]@{ Code = 'food';    Page = 'food';     Id = 6 },
    [pscustomobject]@{ Code = 'toy';     Page = 'toys';     Id = 7 },
    [pscustomobject]@{ Code = 'gift';    Page = 'gifts';    Id = 8 },
    [pscustomobject]@{ Code = 'sticker'; Page = 'stickers'; Id = 9 },
    [pscustomobject]@{ Code = 'house';   Page = 'houses';   Id = 10 }
)

$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'

function ConvertFrom-HtmlEntities {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text
    $t = $t -replace '&#x27;', "'"
    $t = $t -replace '&#39;',  "'"
    $t = $t -replace '&quot;', '"'
    $t = $t -replace '&lt;',   '<'
    $t = $t -replace '&gt;',   '>'
    $t = $t -replace '&amp;',  '&'
    return $t
}

function Get-Page {
    param([string]$Url)
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60 -Headers @{
        'User-Agent'      = $UserAgent
        'Accept'          = 'text/html,application/xhtml+xml'
        'Accept-Language' = 'en-US,en;q=0.9'
    }
    return $resp.Content
}

function Parse-Page {
    param([string]$Html, [string]$CategoryCode)

    $items = New-Object System.Collections.Generic.List[object]

    # Every card starts with:  aria-label="View <Name> details" href="/<cat>/<Slug>"
    $parts = $Html -split 'aria-label="View '
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $block = $parts[$i]

        $href = [regex]::Match($block, 'href="/([a-z]+)/([^"]+)"')
        $title = [regex]::Match($block, 'title="([^"]+)">')
        $value = [regex]::Match($block, 'Value</span><span[^>]*>([0-9.]+)</span>')

        if (-not $href.Success -or -not $title.Success -or -not $value.Success) { continue }

        $demandMatch = [regex]::Match($block, 'Demand</span><span[^>]*><span[^>]*>([\u2605\u2606]+)')
        $demand = 0
        if ($demandMatch.Success) {
            $demand = ([regex]::Matches($demandMatch.Groups[1].Value, [char]0x2605)).Count
        }

        $val = 0.0
        [void][double]::TryParse($value.Groups[1].Value, [System.Globalization.NumberStyles]::Float, $Culture, [ref]$val)

        $items.Add([pscustomobject]@{
            name   = (ConvertFrom-HtmlEntities $title.Groups[1].Value)
            value  = $val
            demand = $demand
            cat    = $CategoryCode
            slug   = $href.Groups[2].Value
        })
    }

    return $items
}

$all = New-Object System.Collections.Generic.List[object]
$byName = @{}

foreach ($c in $Categories) {
    $url = "https://amvgg.com/values/$($c.Page)"
    Write-Host ("fetching {0} ..." -f $url) -NoNewline

    $html = Get-Page -Url $url
    $items = Parse-Page -Html $html -CategoryCode $c.Code

    $added = 0
    foreach ($it in $items) {
        $key = $it.name.ToLowerInvariant()
        if ($byName.ContainsKey($key)) { continue }
        $byName[$key] = $true
        $it | Add-Member -NotePropertyName catId -NotePropertyValue $c.Id
        $all.Add($it)
        $added++
    }

    Write-Host (" {0} items ({1} new)" -f $items.Count, $added)
}

if ($all.Count -lt 100) {
    throw "Scrape failed: only $($all.Count) items parsed."
}

# ---------------------------------------------------------------- output files
$valuesDir = Join-Path $Root 'values'
if (-not (Test-Path $valuesDir)) { New-Item -ItemType Directory -Path $valuesDir | Out-Null }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$jsonPath = Join-Path $valuesDir 'pets.json'
$json = $all | Sort-Object -Property @{ Expression = 'value'; Descending = $true } |
        Select-Object name, value, demand, cat, slug |
        ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($jsonPath, $json, $Utf8NoBom)
Write-Host "wrote $jsonPath"

function Format-LuaNumber {
    param([double]$Number)
    return $Number.ToString('0.##########', $Culture)
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('-- Generated by tools/update-values.ps1 on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ' (UTC' + ((Get-Date).ToUniversalTime().ToString('zzz')) + ')')
[void]$sb.AppendLine('-- Source: https://amvgg.com/values  |  unit: Bat Dragon = 5.53')
[void]$sb.AppendLine('-- name = { value, demand, category }')
[void]$sb.AppendLine('return {')

foreach ($it in ($all | Sort-Object -Property @{ Expression = 'value'; Descending = $true })) {
    $name = $it.name.Replace('\', '\\').Replace('"', '\"')
    $val = Format-LuaNumber $it.value
    [void]$sb.AppendLine(('  ["{0}"] = {{{1}, {2}, {3}}},' -f $name, $val, $it.demand, $it.catId))
}

[void]$sb.AppendLine('}')
$luaPath = Join-Path $valuesDir 'values.lua'
[System.IO.File]::WriteAllText($luaPath, $sb.ToString(), $Utf8NoBom)
Write-Host "wrote $luaPath ($($all.Count) entries)"

# ------------------------------------------------------- inject into main script
$mainPath = Join-Path $Root 'AdoptMeTradeBot.lua'
if (Test-Path $mainPath) {
    $main = Get-Content -Path $mainPath -Raw -Encoding UTF8
    $beginMarker = '-- >>> VALUES_BEGIN'
    $endMarker = '-- <<< VALUES_END'

    $beginIdx = $main.IndexOf($beginMarker)
    $endIdx = $main.IndexOf($endMarker)

    if ($beginIdx -ge 0 -and $endIdx -gt $beginIdx) {
        $inline = New-Object System.Text.StringBuilder
        [void]$inline.AppendLine($beginMarker)
        [void]$inline.AppendLine('-- AUTO-GENERATED - do not edit by hand, run tools/update-values.ps1')
        [void]$inline.AppendLine('local EMBEDDED_VALUES = {')
        foreach ($it in ($all | Sort-Object -Property @{ Expression = 'value'; Descending = $true })) {
            $name = $it.name.Replace('\', '\\').Replace('"', '\"')
            $val = Format-LuaNumber $it.value
            [void]$inline.AppendLine(('    ["{0}"] = {{{1}, {2}, {3}}},' -f $name, $val, $it.demand, $it.catId))
        }
        [void]$inline.AppendLine('}')
        [void]$inline.AppendLine($endMarker)

        $before = $main.Substring(0, $beginIdx)
        $after = $main.Substring($endIdx + $endMarker.Length)
        $newMain = $before + $inline.ToString().TrimEnd() + "`r`n" + $after

        [System.IO.File]::WriteAllText($mainPath, $newMain, $Utf8NoBom)
        Write-Host "injected $($all.Count) values into $mainPath"
    }
    else {
        Write-Warning "markers not found in AdoptMeTradeBot.lua - skipped injection"
    }
}

Write-Host ''
Write-Host "done: $($all.Count) items"
