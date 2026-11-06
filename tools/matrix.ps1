# Runs every cross-army matchup in both seats in parallel and prints seat-averaged win rates.
# Usage: powershell -File tools\matrix.ps1 -Godot <path-to-console-exe> [-Games 100] [-First normal] [-Second normal]
param(
	[Parameter(Mandatory = $true)][string]$Godot,
	[int]$Games = 100,
	[string]$First = "normal",
	[string]$Second = "normal",
	[int]$Setup = 0,
	[string]$Layout = "column",
	[int]$Width = 7,
	[int]$Height = 7
)
$project = Split-Path -Parent $PSScriptRoot
$armies = "ironcrest", "ashen", "verdant"
$out = Join-Path $env:TEMP "tcg-matrix-$Layout-$Setup-$Width`x$Height"
New-Item -ItemType Directory -Force $out | Out-Null
$procs = @()
foreach ($a in $armies) {
	foreach ($b in $armies) {
		if ($a -eq $b) { continue }
		$file = Join-Path $out "$a-$b.txt"
		$procs += Start-Process $Godot -ArgumentList @("--headless", "--path", "`"$project`"", "--script", "res://tools/simulate.gd", "--", "games=$Games", "army1=$a", "army2=$b", "setup=$Setup", "layout=$Layout", "width=$Width", "height=$Height", "first=$First", "second=$Second", "seed=1") -RedirectStandardOutput $file -RedirectStandardError "$file.err" -PassThru -WindowStyle Hidden
	}
}
$procs | Wait-Process
function Wins($a, $b) {
	$line = Get-Content (Join-Path $out "$a-$b.txt") | Select-String "P1 wins: (\d+)  P2 wins: (\d+)"
	return @([int]$line.Matches[0].Groups[1].Value, [int]$line.Matches[0].Groups[2].Value)
}
$lengthSum = 0.0; $objective = 0; $commander = 0; $runs = 0
foreach ($a in $armies) {
	foreach ($b in $armies) {
		if ($a -eq $b) { continue }
		$text = Get-Content (Join-Path $out "$a-$b.txt") -Raw
		$runs++
		$lengthSum += [double][regex]::Match($text, "Average length: ([\d.]+)").Groups[1].Value
		$objective += [int][regex]::Match($text, "objectives captured: (\d+)").Groups[1].Value
		$commander += [int][regex]::Match($text, "enemy commander defeated: (\d+)").Groups[1].Value
	}
}
"layout={0} setup={1}: avg length {2:N1} turns, objective wins {3}, commander kills {4}" -f $Layout, $Setup, ($lengthSum / $runs), $objective, $commander
foreach ($pair in @(@("ironcrest", "ashen"), @("ironcrest", "verdant"), @("ashen", "verdant"))) {
	$a = $pair[0]; $b = $pair[1]
	$ab = Wins $a $b
	$ba = Wins $b $a
	$aWins = $ab[0] + $ba[1]
	$total = 2 * $Games
	"{0,-10} vs {1,-10}: {2,5:P1} / {3,5:P1}   (as P1: {4}-{5}, as P2: {6}-{7})" -f $a, $b, ($aWins / $total), (1 - $aWins / $total), $ab[0], $ab[1], $ba[1], $ba[0]
}
