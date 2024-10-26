# Thaumaturgy Auction House Updater for DBRecent value
# See: https://support.tradeskillmaster.com/auctiondb-market-value
using namespace System.Collections.Generic

# Set TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Var's
$working_dir   = 'full directory path to this script. ie: C:\users\batman\desktop\Thaumaturgy'
$lockFile      = "WoW_API_Lock.lock"
$wowTokenTime  = "us_wow_token.txt" 
$wowTimeFile   = "us_wow_lastmodified.txt"
$wowAuctions   = "DBRecent.csv"
$logFile       = "WoW_API_Log.csv"
$wow_client_id = 'your wow client id here'
$wow_client_secret = 'your wow client secret here'
$wow_grant_type = 'client_credentials' 

# github repo
$repoOwner = 'your github username'
$repoName = 'your github repo'
$branch = 'your branch. probably main'
$github_pat = "your github api token"

# Get Thaumaturgy mats used
$thaumMap = [ordered]@{
    '212667' = "Gloom Chitin R1"
    '212668' = "Gloom Chitin R2"
    '210933' = "Aqirite R1"
    '210934' = "Aqirite R2"
    '210796' = "Mycobloom R1"
    '210797' = "Mycobloom R2"
    '224828' = "Weavercloth R1"
    '228231' = "Weavercloth R2"
    '212664' = "Stormcharged Leather R1"
    '212665' = "Stormcharged Leather R2"
    '210805' = "Blessing Blossom R1"
    '210806' = "Blessing Blossom R2"
    '210936' = "Ironclaw Ore R1"
    '210937' = "Ironclaw Ore R2"
    '219946' = "Storm Dust R1"
    '219947' = "Storm Dust R2"
    '210808' = "Arathor's Spear R1"
    '210809' = "Arathor's Spear R2"
    '210802' = "Orbinid R1"
    '210803' = "Orbinid R2"
    '210799' = "Luredrop R1"
    '210800' = "Luredrop R2"
    '210930' = "Bismuth R1"
    '210931' = "Bismuth R2"
    '212514' = "Blasphemite"
    '197722' = "Aerated Phial of Quick Hands"
}

# set location for relative paths
Set-Location $working_dir
$ProgressPreference = 'SilentlyContinue'

### AUCTION HOUSE DATA FUNCTIONS ###

function logIt {
    param
    (
    [Parameter(Mandatory)][string]$status
    )

    [psCustomObject] @{
        'time' = (Get-Date).DateTime
        'status' = $status
    } | Export-Csv -NoTypeInformation -Append -Path $logfile
}

# get Realm AH data
function Get-DBRecent {
   
    #create lock file
    if (Test-Path $lockFile) {
        # stop processing until complete
		# remove lock file and check again if it is older than 10min.
		$lockFileMaxAge = (Get-Date).AddMinutes(-10)
		if ((Get-Item $lockfile).lastwritetime -lt $lockFileMaxAge) { 
			Remove-Item $lockfile -Force
			$Script:updateInProgress = $True
			if (!(Test-Path $lockFile)) {
				New-Item $lockFile | Out-Null
			}
		}
		else {
			$Script:updateInProgress = $True
			logIt "lock file detected"
			exit
		}
    } else {
        New-Item $lockFile | Out-Null
    }

    # check if new data is available
    if (Test-Path $wowTimeFile) { 

        if (Get-Content $wowTimeFile) {
            # time exists to check against
            $timeHeader = Get-Content $wowTimeFile
        } else {
            # time didnt exist so dl anyways
            $timeHeader = "Sun, 22 Sep 2019 12:00:00 GMT"
        }
    } else {
        # timefile did not even exist so download anyways
        $timeHeader = "Sun, 22 Sep 2019 12:00:00 GMT"
    }

    try {
        # get wow api token
        $wowCreds = @{
            client_id = $wow_client_id
            client_secret = $wow_client_secret 
            grant_type = $wow_grant_type
        }
        
        # Only get wow token again if last one is expired, otherwise use existing
        if (Test-Path $wowTokenTime) { 

            $lastTokenValidity = Import-Csv -Path $wowTokenTime
            if ( (Get-Date) -lt ([datetime]$lastTokenValidity.expires_in) ) {
                # Current token is good
                $tokenData = $lastTokenValidity
            } else {
                # token expired, get again
                $tokenData = Invoke-RestMethod "https://us.battle.net/oauth/token" -Body $wowCreds -Method Post
                $tokenData.expires_in = (Get-Date).AddSeconds($tokenData.expires_in)
                $tokenData | Export-Csv -Path $wowTokenTime -NoTypeInformation -Force
                logit "WoW Token Expired. Getting a new one"
            }
        } else {
            # timefile did not exist so get token again
            $tokenData = Invoke-RestMethod "https://us.battle.net/oauth/token" -Body $wowCreds -Method Post
            $tokenData.expires_in = (Get-Date).AddSeconds($tokenData.expires_in)
            $tokenData | Export-Csv -Path $wowTokenTime -NoTypeInformation -Force
            logit "No WoW Token Found. Getting a new one"
        }
        # dl or check ah data for new data
	$wowHeaders = @{
            'Authorization' = "Bearer $($tokenData.access_token)"
            'If-Modified-Since' = $timeHeader
        }
        $ahJson = Invoke-WebRequest -Uri "https://us.api.blizzard.com/data/wow/auctions/commodities?namespace=dynamic-us&locale=en_US" -Headers $wowHeaders -ContentType application/json
    } Catch {
        $responseAll = $_.Exception.Response
		if (Test-Path $lockFile) {
			Remove-Item $lockFile -Force | Out-Null
		}
    }

    #if download was good, proceed
    if ($ahJson.StatusCode -eq "200") {
        
        $AH = $ahJson.content | ConvertFrom-Json
        logIt "Blizz US Region AH download completed successfully"

        # get the lastupdated header
        $ahJson.Headers.'Last-Modified' | Out-File $wowTimeFile -Force
    
        # Collect just the thaum mats
        $thaumMats = [List[object]]::new()
        foreach ($i in $AH.auctions) {
            if ($i.item.id -in $thaumMap.Keys) {
                $thaumMats.Add(
                    [PSCustomObject]@{
                        itemId    = $i.item.id
                        quantity  = [int64]$i.quantity
                        unitPrice = [int64]$i.unit_price
                    }
                )
            }
        }

        # group by itemid
        $thaumMatsGrouped = $thaumMats | Group-Object -Property itemId

        # calculate total quantities
        # Step 1
        $thaumMatsRefined = [List[object]]::new()
        Foreach ($g in $thaumMatsGrouped) {

            $totalQuantity = ($g.group.quantity | Measure-Object -Sum).Sum
            $itemQ = [PSCustomObject]@{
                'ItemData'      = $g.group
                'TotalQuantity' = [int]$totalQuantity
                'TotalAuctions' = [int]$g.count
                '15p'           = [Math]::Round(0.15 * $TotalQuantity,2)
                '30p'           = [Math]::Round(0.30 * $TotalQuantity,2)
            }
            $thaumMatsRefined.Add($itemQ)
        }

        # test set: {5, 13, 13, 15, 15, 15, 16, 17, 17, 19, 20, 20, 20, 20, 20, 20, 21, 21, 29, 45, 45, 46, 47, 100} = 14.5 dbrecent
        # keep everything up until (and incl) 15% quantity, then only keep up to (and incl) 30% only if next price is not higher than a 20% jump
        $thaumMatsMath = [List[object]]::new()
        foreach ($grp in $thaumMatsRefined) {
            $runningQ = 0
            $lastRunningQ = 0
            $lastPrice = 0
            $sortedByPrice = $grp.ItemData | Sort-Object -Property unitprice
            Foreach ($mat in $sortedByPrice) {
                $currentQuantity = [int]$mat.quantity
                $runningQ = $runningQ + $currentQuantity
                # Add first 15% no matter what
                if ($runningQ -le $grp.'15p') {
                    $thaumMatsMath.Add($mat)
                # start checking from 15-30% if next amount is less than a 20% diff and if so add. If not, stop.
                } elseif ($runningQ -le $grp.'30p') {
                    if ( $mat.unitprice -lt ($lastPrice * 1.20) ) {
                        $thaumMatsMath.Add($mat)
                    } else {
                        # greater than or equal to a 20% price jump, stop adding.
                        write-host "stopped due to 20% increase. last mat price was $lastPrice and next price would have been $($mat.unitprice)"
                        Break
                    }
                } else {
                    $addTo30p = $grp.'30p' - $lastRunningQ
                    if ($addTo30p -le $currentQuantity) {
                        $mat.quantity = $addTo30p
                        Write-Host "added $addTo30p more to reach 30%. Last mat added is $mat"
                        $thaumMatsMath.Add($mat)
                    } else {
                        Write-Host "I should probably never see this message"
                    }
                    # Stop adding anything over 30%
                    write-host "stopped due to reaching 30%"
                    Break
                }
                $lastPrice = $mat.unitprice 
                $lastRunningQ = $runningQ
            }
        }

        # regroup them for next maths
        $thaumMatsGrouped2 = $thaumMatsMath | Group-Object -Property itemId

        # calculate averages and standard deviation
        # Step 2
        $finalData = [List[object]]::new()
        Foreach ($g in $thaumMatsGrouped2) {

            $dataPoints = [List[object]]::new()
            $avg = ($g.group.unitPrice | Measure-Object -Average).Average
            $variance = ($g.group.unitPrice | ForEach-Object { [Math]::Pow(($_ - $avg), 2) } | Measure-Object -Average).Average
            $stdDev = [math]::Sqrt($variance)
            $lowerBoundary = $avg - ($stdDev * 1.5)
            $upperBoundary = $avg + ($stdDev * 1.5)
            ForEach ($price in $g.group.unitPrice) {
                if ( ($price -ge $lowerBoundary) -and ($price -le $upperBoundary) ) { # these maybe should be lt and gt, but then have to have logic for if pricees are all the same.
                    # keep the data point
                    $dataPoints.Add($price)
                }
            }
            # take avg of remaining datapoints
            # Step 3
            $dbRecent = ($dataPoints | Measure-Object -Average).Average

            $finalData.Add([PSCustomObject]@{
                'Name'     = $thaumMap[$g.Name]
                'ItemId'   = $g.Name
                'DBRecent' = [Math]::Round($dbRecent/10000, 2)
            })
        }

        # add timestamp and export as csv
        $lastMod = [datetime]::ParseExact($ahJson.Headers.'Last-Modified', "ddd, dd MMM yyyy HH:mm:ss 'GMT'", $Null)
        $finalData.Add([PSCustomObject]@{
            'Name'     = "Updated"
            'ItemId'   = Get-Date $lastMod -Format "MM/dd/yyyy"
            'DBRecent' = Get-Date $lastMod -Format "HH:mm:ss"
        })
        $finalData | Export-Csv $wowAuctions -NoTypeInformation
        logIt "Blizz DBRecent Export completed successfully"

        # clean up
        $removeVar = @('AH', 'ahJson', 'thaumMats', 'thaumMatsGrouped')
        Remove-Variable $removeVar -Force
        [GC]::Collect()

    } elseif ($responseAll.StatusCode.value__ -eq '304' ){
        # remove lock file
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force
        }
        logIt "WOW - Data is already up to date. Not re-downloading yet."
        exit
    } else {
        # remove lock file
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force
        }
        logIt "Error Accessing Blizzard API:"
	logIt "$($responseAll.StatusCode) `n$($responseAll.ReasonPhrase)"
        exit
    }
    # remove lock file
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
}

# Note. I did not include code for initial file creation. Only for updating existing. So just manually create the file one time and then good to go.
Function Start-Upload {

    $filePath = $filePath = Join-Path -Path $pwd -ChildPath $wowAuctions
    $fileContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($filePath))
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/contents/$fileName"

    # Get current file info
    $currentFile = Invoke-RestMethod -Uri $apiUrl -Headers @{
        Authorization = "token $github_pat"
        "User-Agent" = "Pwsh"
    }

    # JSON body for API call
    $jsonBody = @{
        message = "Update $fileName"
        content = $fileContent
        branch = $branch
        sha = $currentFile.sha
    } | ConvertTo-Json

    # Upload
    $githubHeaders = @{
        'Authorization' = "token $github_pat"
        'User-Agent' = "Pwsh"    
    }
    $upload = Invoke-RestMethod -Uri $apiUrl -Method Put -Headers $githubHeaders -Body $jsonBody -ContentType application/json

    # Output the response
    if ($upload.content.name -eq 'DBRecent.csv') {
        logIt "DBRecent file uploaded to Github Successfully"
    } else {
        logIt "DBRecent file FAILED to upload to Github"
    }
}

# Run it
Get-DBRecent
Start-Upload
