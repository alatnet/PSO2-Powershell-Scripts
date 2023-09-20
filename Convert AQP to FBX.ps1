Param(
    [Parameter(Position=0, Mandatory, ValueFromPipeline)]
    [string]$Model, #model
    [Parameter()]
    [string[]]$Anims = @(), #animations
    #[Parameter()]
    #[switch]$IncludeMetadata = $true,
    [Parameter(Mandatory)]
    [string]$AMLib = "AquaModelLibrary.dll" #Aqua Model Tool Library
)

#Misc Funcs
function Resolve-Error ($ErrorRecord=$Error[0])
{
   $ErrorRecord | Format-List * -Force
   $ErrorRecord.InvocationInfo |Format-List *
   $Exception = $ErrorRecord.Exception
   for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
   {   "$i" * 80
       $Exception |Format-List * -Force
   }
}

function Write-Color([String[]]$Text, [ConsoleColor[]]$Color) {
    for ($i = 0; $i -lt $Text.Length; $i++) {
        Write-Host $Text[$i] -Foreground $Color[$i] -NoNewLine
    }
    Write-Host
}

#initialize the aqua model library.
#Begin {
    Write-Color -Text "AquaModelLibrary Path: ", "$($AMLib)" -Color White,Green

    #Load the Library
    $AMLibAsm = Add-Type -Path $AMLib -PassThru
    
    #Create a new AquaUtility
    $aquaUtil = New-Object AquaModelLibrary.AquaUtil
#}

#for every entry, convert them into an fbx file.
#Process {
    $ext = [System.IO.Path]::GetExtension($Model)
    $OutPath = [System.IO.Path]::ChangeExtension($Model, ".fbx")

    #delete the old fbx file
    if (Test-Path $OutPath){
        Remove-Item $OutPath
    }

    Write-Color -Text "Model Path: ","$($Model)" -Color White,Green
    Write-Color -Text "Output Path: ","$($OutPath)" -Color White,Green

    $aquaUtil.aquaModels.Clear() #clear out the model

    #read the model
    try {
        $ModelErr = $aquaUtil.ReadModel($Model, $false)
    } catch {
        Write-Error "Could not load model."
        exit 1
    }

    #read the bones
    $boneExt = ""

    $aquaUtil.aquaBones.Clear() #clear out the bones

    switch($ext){
        ".aqo" { $boneExt = ".aqn" ; Break }
        ".aqp" { $boneExt = ".aqn" ; Break }
        ".tro" { $boneExt = ".trn" ; Break }
        ".trp" { $boneExt = ".trn" ; Break }
        default {
            Write-Warning "Could not determine bone file, defaulting to single node placeholder."
            $aquaUtil.aquaBones.Add([AquaModelLibrary.AquaNode]::GenerateBasicAQN()) #generate a default bone system
            Break
        }
    }

    if ($boneExt -ne ""){
        $bonePath = [System.IO.Path]::ChangeExtension($Model, $boneExt)

        Write-Color -Text "Bone Path: ","$($bonePath)" -Color White,Green

        if(Test-Path -Path $bonePath){
            try {
                $aquaUtil.ReadBones($bonePath)
            } catch {
                Write-Warning "Must be able to read bones to export properly! Defaulting to single node placeholder."
                $aquaUtil.aquaBones.Add([AquaModelLibrary.AquaNode]::GenerateBasicAQN()) #generate a default bone system
            }
        } else {
            Write-Warning "Must be able to read bones to export properly! Defaulting to single node placeholder."
            $aquaUtil.aquaBones.Add([AquaModelLibrary.AquaNode]::GenerateBasicAQN()) #generate a default bone system
        }
    }


    #.aqm files
    #read the animations
    $MotionList = New-Object 'System.Collections.Generic.List[AquaModelLibrary.AquaMotion]'
    $MotionNameList = New-Object 'System.Collections.Generic.List[System.String]'

    if ($Anims.Count -gt 0){ #if we have a list of animations
        Write-Host "Animations Paths:"
        foreach($anim in $Anims){
            Write-Color -Text "- ", "$($anim)" -Color White,Green
        }

        foreach($anim in $Anims){
            $aquaUtil.aquaMotions.Clear() #clear out the animations
            try {
                $aquaUtil.ReadMotion($anim)
            } catch {
                Write-Warning "Could not read animation: $($anim)"
                continue
            }
            $MotionList.Add($aquaUtil.aquaMotions[0].anims[0])
            $MotionNameList.Add([System.IO.Path]::GetFileName($anim))
        }
    } else { #determine if there is an animation
        $animPath = [System.IO.Path]::ChangeExtension($Model, ".aqm")

        Write-Color -Text "Auto detecting Anim Path: ","$($animPath)" -Color White,Green

        if (Test-Path $animPath){
            Write-Host "-Anim Path is Valid, adding Animations." -ForegroundColor Green
            
            $aquaUtil.aquaMotions.Clear() #clear out the animations
            try {
                $aquaUtil.ReadMotion($animPath)
                $MotionList.Add($aquaUtil.aquaMotions[0].anims[0])
                $MotionNameList.Add([System.IO.Path]::GetFileName($animPath))
            } catch {
                Write-Warning "Could not read animation: $($animPath)"
            }

        } else {
            Write-Host "-Anim Path is Not Valid, skipping adding Animations." -ForegroundColor Red
        }
    }

    #fix up the model
    if ($aquaUtil.aquaModels[0].models[0].objc.type > 0xC32){
        $aquaUtil.aquaModels[0].models[0].splitVSETPerMesh()
    }

    $aquaUtil.aquaModels[0].models[0].FixHollowMatNaming()

    try {
        #convert to fbx
        [AquaModelLibrary.Native.Fbx.FbxExporter]::ExportToFile(
            $aquaUtil.aquaModels[0].models[0],
            $aquaUtil.aquaBones[0],
            $MotionList,
            $OutPath,
            $MotionNameList,
            $true #$IncludeMetadata
        )
    } catch {
        Resolve-Error ($Error[0])
    }
#}