# ConvertTo-Png - Converts image files to PNG format
# https://github.com/jimminning/ConvertTo-Png

# Modified from https://github.com/DavidAnson/ConvertTo-Jpeg

Param (
        [Parameter(
            Mandatory = $true,
            Position = 1,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ValueFromRemainingArguments = $true,
            HelpMessage = "Array of image files to convert to PNG")]
        [Alias("FullName")]
        [String[]]
        $Files
    )

    Begin
    {
        # Technique for await-ing WinRT APIs: https://fleexlab.blogspot.com/2018/02/using-winrts-iasyncoperation-in.html
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $runtimeMethods = [System.WindowsRuntimeSystemExtensions].GetMethods()
        $asTaskGeneric = ($runtimeMethods | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        Function AwaitOperation ($WinRtTask, $ResultType)
        {
            $asTaskSpecific = $asTaskGeneric.MakeGenericMethod($ResultType)
            $netTask = $asTaskSpecific.Invoke($null, @($WinRtTask))
            $netTask.Wait() | Out-Null
            $netTask.Result
        }
        $asTask = ($runtimeMethods | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
        Function AwaitAction ($WinRtTask)
        {
            $netTask = $asTask.Invoke($null, @($WinRtTask))
            $netTask.Wait() | Out-Null
        }

        # Reference WinRT assemblies
        [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
    }

    Process
    {
        # Summary of imaging APIs: https://docs.microsoft.com/en-us/windows/uwp/audio-video-camera/imaging
        
        foreach ($file in $Files)
        {
            Write-Host $file -NoNewline
            try
            {
                try
                {
                    # Get SoftwareBitmap from input file
                    $file = Resolve-Path -LiteralPath $file
                    $inputFile = AwaitOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($file)) ([Windows.Storage.StorageFile])
                    $inputFolder = AwaitOperation ($inputFile.GetParentAsync()) ([Windows.Storage.StorageFolder])
                    $inputStream = AwaitOperation ($inputFile.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                    $decoder = AwaitOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($inputStream)) ([Windows.Graphics.Imaging.BitmapDecoder])
                }
                catch
                {
                    # Ignore non-image files
                    Write-Host " [Unsupported]"
                    continue
                }
                if ($decoder.DecoderInformation.CodecId -eq [Windows.Graphics.Imaging.BitmapDecoder]::PngDecoderId)
                {
                    # Skip PNG-encoded files
                    Write-Host " [Already PNG]"
                    continue
                }
                $bitmap = AwaitOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

                # Write SoftwareBitmap to output file
                $outputFileName = $inputFile.Name -replace ($inputFile.FileType + "$"), ".png"
                $outputFile = AwaitOperation ($inputFolder.CreateFileAsync($outputFileName, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
                $outputStream = AwaitOperation ($outputFile.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
                $encoder = AwaitOperation ([Windows.Graphics.Imaging.BitmapEncoder]::CreateAsync([Windows.Graphics.Imaging.BitmapEncoder]::PngEncoderId, $outputStream)) ([Windows.Graphics.Imaging.BitmapEncoder])
                $encoder.SetSoftwareBitmap($bitmap)
                $encoder.IsThumbnailGenerated = $false #PNG encoder doesn't like the thumbnail generation

                # Do it
                AwaitAction($encoder.FlushAsync())
                Write-Host " -> $outputFileName"
            }
            catch
            {
                # Report full details
                throw $_.Exception.ToString()
            }
            finally
            {
                # Clean-up
                if ($inputStream -ne $null) { [System.IDisposable]$inputStream.Dispose() }
                if ($outputStream -ne $null) { [System.IDisposable]$outputStream.Dispose() }
            }
        }
    }