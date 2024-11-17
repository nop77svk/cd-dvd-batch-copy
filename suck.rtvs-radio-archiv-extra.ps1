$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'
$DebugPreference = 'SilentlyContinue'

class SourceDefinition
{
	[string] $Name
    [string] $URI
}

$SourceBaseUri = 'https://www.rtvs.sk'

$SourceDefinitions = @(
    [SourceDefinition]@{
        Name = 'Rozhlasové hry';
        URI = '/radio/archiv/extra/rozhlasove-hry'
    },
    [SourceDefinition]@{
        Name = 'Rozprávky';
        URI = '/radio/archiv/extra/rozpravky'
    },
    [SourceDefinition]@{
        Name = 'Čítanie na pokračovanie';
        URI = '/radio/archiv/extra/citanie-na-pokracovanie'
    }
)

function Scrape-TheSources()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$input
	)

	process
	{
		Write-Information "[SOURCE] $( $input.Name )"

	    $classRootPageUri = "$SourceBaseUri$( $input.URI )"
	    Write-Debug "[GET] $classRootPageUri"

	    $classRootPage = Invoke-WebRequest -Uri $classRootPageUri -Method Get

	    $classRootPage.Links
	        | Where-Object { $_.class -eq 'page-link' -and $_.id -eq 'pageSwitcher' }
	        | Select-Object -ExpandProperty href
	        | Select-String -Pattern '[?&]page=(\d+)'
	        | ForEach-Object {[PSCustomObject]@{
	            HRef = $_.Line
	            PageIx = [int]$_.Matches.Groups[1].Captures[0].Value
	        }}
	        | Sort-Object -Descending PageIx
	        | Select-Object -First 1
			| %{ [PSCustomObject]@{
				SourceDef = $input;
				LastPageDesc = $_
			}}
	}
}

function Scrape-TheSourcePaging()
{
	param (
		[Parameter(Mandatory, ValueFromPipeline)]
		$input
	)

	process
	{
	    for ([int]$pageIx = 1; $pageIx -le $input.LastPageDesc.PageIx; $pageIx++)
	    {
	        Write-Information "[PAGE NO] $pageIx"

	        $rootSubpageRelativeUri = $input.LastPageDesc.HRef -replace $input.LastPageDesc.PageIx,$pageIx
	        $rootSubpageUri = "$SourceBaseUri$rootSubpageRelativeUri"

	        Write-Debug "[GET] $rootSubpageUri"
	        $rootSubpage = Invoke-WebRequest -Uri $rootSubpageUri -Method Get

	        $rootSubpage.Links
	            | Where-Object { $_.class -eq 'list--radio-series__link' -and -not [string]::IsNullOrEmpty($_.title) }
				| %{ [PSCustomObject]@{
					SourceDef = $input.SourceDef;
					LastPageDesc = $input.LastPageDesc;
					SingleSeriesLink = [PSCustomObject]@{
						Title = $_.title;
						Href = $_.href
					}
				}}
		}
	}
}
	

$SourceDefinitions
	| Scrape-TheSources
	| Scrape-TheSourcePaging
	| Scrape-TheSeriesLinks
<#    
        foreach ($singleSeriesLink in $seriesLinks)
        {
            Write-Information "[SERIES] $( $singleSeriesLink.title )"
            $seriesPartPageUri = "$SourceBaseUri$( $singleSeriesLink.href )"

            Write-Debug "[GET] $seriesPartPageUri"
            $seriesPartPage = Invoke-WebRequest -Uri $seriesPartPageUri -Method Get

            $audioIframeUris = $seriesPartPage.RawContent -split "`n"
                | Select-String -Pattern '<iframe[^>]*\s+id\s*=\s*"player_audio_\d+"[^>]*>'
                | %{ $_.Matches[0] }
                | Select-Object -ExpandProperty Value
                | Select-String -Pattern 'src\s*=\s*"([^"]*)"'
                | %{ $_.Matches[0].Groups[1] }
                | Select-Object -ExpandProperty Value
            
            foreach ($singleAudioIframeUri in $audioIframeUris)
            {
                Write-Debug "[GET] $singleAudioIframeUri"
                $audioIframePage = Invoke-WebRequest -Uri $singleAudioIframeUri -Method Get

                $audioJsonRelativeUris = $audioIframePage.RawContent -split "`n"
                    | Select-String -Pattern '[^"]+\.json\?id=\d+'
                    | %{ $_.Matches[0].Value }

                foreach ($singleJsonUri in $audioJsonRelativeUris)
                {
                    if ($singleJsonUri -like '//*')
                    {
                        $singleJsonUri = "https:$singleJsonUri"
                    }

                    Write-Debug "[GET] $singleJsonUri"
                    $audioJson = Invoke-RestMethod -Uri $singleJsonUri -Method Get

                    foreach ($mediaFile in $audioJson.playlist)
                    {
                        Write-Debug "[PLAYLIST ITEM] $mediaFile"

                        $sourceNo = 0
                        foreach ($mediaSource in $mediaFile.sources)
                        {
                            Write-Debug "[SOURCE $sourceNo] $mediaSource"

                            $fileName = "e:\$( $singleSeriesLink.title ).part-$sourceNo.mp3" # decide extension based on mime type in the .type property
                            Write-Debug "[OUTPUT] $fileName"

                            Invoke-WebRequest -Uri $mediaSource.src -Method Get -OutFile $fileName
                        }
                    }
                }
            }
        }
    }
#>
