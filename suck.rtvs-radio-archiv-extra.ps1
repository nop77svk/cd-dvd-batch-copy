param (
	[string] $OutputPath
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'
#$DebugPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'

$SourceBaseUri = 'https://www.rtvs.sk'
$MaxConcurrentDownloads = 1 * ${env:NUMBER_OF_PROCESSORS}

# ------------------------------------------------------------------------------------------------

if ($null -eq $OutputPath)
{
	$OutputPath = Join-Path ${env:USERPROFILE} "Documents"
}

$MediaInfoStoragePath = Join-Path $OutputPath "suck.rtvs-radio-archiv-extra.json"

class MediaInfoItem
{
    [string] $Id
    [DateTime] $Created
    [DateTime] $Updated
    [string] $Title
}

[hashtable]$global:MediaInfoStorage = $null

function Write-FullIdToStorage([string] $id, [string] $name)
{
    if ($null -eq $global:MediaInfoStorage)
    {
        if ([System.IO.File]::Exists($MediaInfoStoragePath))
        {
            $global:MediaInfoStorage = @{}
            Get-Content $MediaInfoStoragePath
                | ConvertFrom-Json
                | ForEach-Object { $global:MediaInfoStorage[$_.Id] = $_ }
        }

        if ($null -eq $global:MediaInfoStorage)
        {
            $global:MediaInfoStorage = @{}
        }
    }

    $item = $global:MediaInfoStorage[$id]
    if ($null -eq $item)
    {
        $item = [MediaInfoItem]@{
            Created = [datetime]::Now
        }
    }
    else
    {
        [MediaInfoItem]$item = $item
    }

    $item.Id = $id
    $item.Updated = [datetime]::Now
    $item.Title = $title

    $global:MediaInfoStorage[$id] = $item

    $global:MediaInfoStorage.GetEnumerator()
        | Select-Object -ExpandProperty Value
        | Sort-Object -Property Created
        | ConvertTo-Json
        | Set-Content -Path $MediaInfoStoragePath
}

class SourceDefinition
{
    [string] $Id
	[string] $Name
    [string] $URI
}

$SourceDefinitions = @(
    [SourceDefinition]@{
        Id = 'rozhlasove-hry';
        Name = 'Rozhlasové hry';
        URI = '/radio/archiv/extra/rozhlasove-hry'
    },
    [SourceDefinition]@{
        Id = 'rozpravky';
        Name = 'Rozprávky';
        URI = '/radio/archiv/extra/rozpravky'
    },
    [SourceDefinition]@{
        Id = 'citanie-na-pokracovanie';
        Name = 'Čítanie na pokračovanie';
        URI = '/radio/archiv/extra/citanie-na-pokracovanie'
    }
)

function Read-TheSources()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$data
	)

	process
	{
        $dataRow = $_
		Write-Information "[SOURCE] $( $dataRow.Name )"

	    $classRootPageUri = "$SourceBaseUri$( $dataRow.URI )"
	    Write-Debug "[GET] $classRootPageUri"

	    $classRootPage = Invoke-WebRequest -Uri $classRootPageUri -Method Get

	    $result = $classRootPage.Links
	        | Where-Object { $_.class -eq 'page-link' -and $_.id -eq 'pageSwitcher' }
	        | Select-Object -ExpandProperty href
	        | Select-String -Pattern '[?&]page=(\d+)'
	        | ForEach-Object {[PSCustomObject]@{
	            HRef = $_.Line
	            PageIx = [int]$_.Matches.Groups[1].Captures[0].Value
	        }}
	        | Sort-Object -Descending PageIx
	        | Select-Object -First 1
			| ForEach-Object { [PSCustomObject]@{
				Source = $dataRow;
				LastPage = $_
			}}
        
        $result
	}
}

function Select-Paging()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$data
	)

    process
    {
        $dataRow = $_

	    for ([int]$pageIx = $dataRow.LastPage.PageIx; $pageIx -gt 0; $pageIx--)
	    {
	        Write-Information "[SOURCE PAGE] $pageIx"

	        $rootSubpageRelativeUri = $dataRow.LastPage.HRef -replace $dataRow.LastPage.PageIx,$pageIx
	        $rootSubpageUri = "$SourceBaseUri$rootSubpageRelativeUri"

            $result = [PSCustomObject]@{
                Source = $dataRow.Source;
                Page = [PSCustomObject]@{
                    Id = $pageIx;
                    LastId = $dataRow.LastPage.PageIx
                    Uri = $rootSubpageUri;
                }
            }

            $result
        }
    }
}

class SingleSeriesLink
{
    [string] $Id
    [string] $Title
    [string] $PageHref
    [string] $IFrameHref
    [string] $AudioJsonUri
    [int] $MediaSourceId
    [string] $MediaSourceMimeType
    [string] $MediaSourceUri

    [SingleSeriesLink] WithIFrameHref([string] $uri)
    {
        $this.IFrameHref = $uri
        return $this
    }

    [SingleSeriesLink] WithAudioJsonUri([string] $uri)
    {
        $this.AudioJsonUri = $uri
        return $this
    }

    [SingleSeriesLink] WithMediaSource([int] $id, [string] $mimeType, [string] $uri)
    {
        $this.MediaSourceId = $id
        $this.MediaSourceMimeType = $mimeType
        $this.MediaSourceUri = $uri
        return $this;
    }

    [string] GetMediaFileExtension()
    {
        $result = switch ($this.MediaSourceMimeType)
        {
            'audio/mp3' { 'mp3' }
            default { 'bin' }
        }

        return $result
    }

    [string] GetOutputFileName()
    {
        $fileBaseName = $this.Title.Replace('/','--').Replace('?','_').Replace(':',' - ').Trim() -replace '\s+',' '
        $fileSuffix = $this.MediaSourceId.ToString()
        $fileExtension = $this.GetMediaFileExtension()

        $result = "$fileBaseName [$fileSuffix].$fileExtension"

        return $result
    }
}

function Read-TheSourcePaging()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$data
	)

	process
	{
        $dataRow = $_

        Write-Debug "[GET] $( $dataRow.Page.Uri )"
        $rootSubpage = Invoke-WebRequest -Uri $dataRow.Page.Uri -Method Get

        $result = $rootSubpage.Links
            | Where-Object { $_.class -eq 'list--radio-series__link' -and -not [string]::IsNullOrEmpty($_.title) }
            | ForEach-Object { [PSCustomObject]@{
                Source = $dataRow.Source;
                Page = $dataRow.Page;
                SingleSeriesLink = [SingleSeriesLink]@{
                    Id = $_.href -replace '^.*/(\d+)/(\d+)$','$1-$2'
                    Title = $_.title
                    PageHref = $_.href
                }
            }}
        
        $result
	}
}

function Read-TheSeriesLinks()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$data
	)

	process
	{
        $dataRow = $_

        Write-Information "[SERIES] $( $dataRow.SingleSeriesLink.Title )"
        $seriesPartPageUri = "$SourceBaseUri$( $dataRow.SingleSeriesLink.PageHref )"

        Write-Debug "[GET] $seriesPartPageUri"
        $seriesPartPage = Invoke-WebRequest -Uri $seriesPartPageUri -Method Get

        $iframeHtmls = $seriesPartPage.Content -split "`n"
            | ForEach-Object { $_.Trim() }
            | Select-String -Pattern '<iframe[^>]*\s+id\s*=\s*"player_audio_\d+"[^>]*>'
        
        $iframeHrefs = $iframeHtmls
            | ForEach-Object { $_.Matches[0] }
            | Select-Object -ExpandProperty Value
            | Select-String -Pattern 'src\s*=\s*"([^"]*)"'
            | ForEach-Object { $_.Matches[0].Groups[1] }
            | Select-Object -ExpandProperty Value

        $result = $iframeHrefs
            | ForEach-Object { [PSCustomObject]@{
                Source = $dataRow.Source;
                Page = $dataRow.Page;
                SingleSeriesLink = $dataRow.SingleSeriesLink.WithIFrameHref($iframeHrefs)
            }}
        
        $result
    }
}

function Read-TheAudioIFrames()
{
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $data
    )

    process
    {
        $dataRow = $_

        $singleAudioIframeUri = $dataRow.SingleSeriesLink.IFrameHref
        Write-Debug "[GET] $singleAudioIframeUri"
        $audioIframePage = Invoke-WebRequest -Uri $singleAudioIframeUri -Method Get

        $audioJsonUris = $audioIframePage.Content -split "`n"
            | Select-String -Pattern '[^"]+\.json\?id=\d+'
            | ForEach-Object { $_.Matches[0].Value }
            | ForEach-Object { $_ -like '//*' ? "https:$_" : $_ }

        $result = $audioJsonUris
            | ForEach-Object { [PSCustomObject]@{
                Source = $dataRow.Source;
                Page = $dataRow.Page;
                SingleSeriesLink = $dataRow.SingleSeriesLink.WithAudioJsonUri($_)
            }}

        $result
    }
}

function Read-TheAudioJsons()
{
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $data
    )

    process
    {
        $dataRow = $_

        $singleJsonUri = $dataRow.SingleSeriesLink.AudioJsonUri
        Write-Debug "[GET] $singleJsonUri"
        $audioJson = Invoke-RestMethod -Uri $singleJsonUri -Method Get

        $playlistItemId = 0
        $mediaSourceItemId = 0
        $result = $audioJson.playlist
            | ForEach-Object { $playlistItemId++; Write-Debug "[PLAYLIST ITEM $playlistItemId] $_"; $_ }
            | Select-Object -ExpandProperty sources
            | ForEach-Object { $mediaSourceItemId++; Write-Debug "[MEDIA SOURCE $mediaSourceItemId] $_"; $_ }
            | ForEach-Object { [PSCustomObject]@{
                Source = $dataRow.Source;
                Page = $dataRow.Page;
                SingleSeriesLink = $dataRow.SingleSeriesLink.WithMediaSource($mediaSourceItemId, $_.type, $_.src)
            }}

        $result
    }
}


$jobs = $SourceDefinitions
    | Read-TheSources
    | Select-Paging
    | Read-TheSourcePaging
    | Read-TheSeriesLinks
    | Read-TheAudioIFrames
    | Read-TheAudioJsons
    | Select-Object -First 10
    | ForEach-Object {
        $mediaSourceFullId = "$( $_.Source.Id ).$( $_.SingleSeriesLink.Id ).$( $_.SingleSeriesLink.MediaSourceId )"

        if ($null -ne $global:MediaInfoStorage -and $global:MediaInfoStorage.ContainsKey($mediaSourceFullId))
        {
            Write-Warning "[ALREADY DOWNLOADED] $mediaSourceFullId"
        }
        else
        {
            Write-Debug "[MEDIA SOURCE FULL ID] $mediaSourceFullId"

            $jobBody = {
                param (
                    [string] $mediaSourceUri,
                    [string] $mediaOutputFileName,
                    [string] $mediaSourceFullId,
                    [string] $title
                )

                Write-Debug "[GET] $mediaSourceUri"
                Write-Debug "[OUTPUT] $mediaOutputFileName"

                Invoke-WebRequest -Uri $mediaSourceUri -Method Get -OutFile $mediaOutputFileName

                Write-FullIdToStorage -id $mediaSourceFullId -title $title
            }

            New-Item -Path $OutputPath -Name $_.Source.Id -Force -ItemType Directory
            $mediaOutputFileName = Join-Path $OutputPath $_.Source.Id $_.SingleSeriesLink.GetOutputFileName()

            # Start-ThreadJob -ThrottleLimit $MaxConcurrentDownloads -Name $mediaSourceFullId -ArgumentList "e:",$_.SingleSeriesLink -ScriptBlock $jobBody
            Invoke-Command -ScriptBlock $jobBody -ArgumentList $_.SingleSeriesLink.MediaSourceUri,$mediaOutputFileName,$mediaSourceFullId,$_.SingleSeriesLink.Title
        }
    }

# Receive-Job -Job $jobs -AutoRemoveJob -Wait
