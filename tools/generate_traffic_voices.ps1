$ErrorActionPreference='Stop'
$trafficFolder=Join-Path $PSScriptRoot '../project/audio/traffic'
New-Item -ItemType Directory -Path $trafficFolder -Force | Out-Null
$trafficVoice=New-Object -ComObject SAPI.SpVoice
foreach($installedVoice in $trafficVoice.GetVoices()) { if($installedVoice.GetDescription() -match 'Sabina|Spanish|Espa') { $trafficVoice.Voice=$installedVoice;break } }
$trafficVoice.Rate=1
$phrases=@('¡Avanza, pe!','¡Deja pasar!','¡Muévete, carajo!','¡No te quedes ahí!')
for($phraseIndex=0;$phraseIndex -lt $phrases.Count;$phraseIndex++) {
 $trafficOutput=New-Object -ComObject SAPI.SpFileStream
 $trafficOutput.Open((Join-Path $trafficFolder ('driver_'+$phraseIndex+'.wav')),3,$false)
 $trafficVoice.AudioOutputStream=$trafficOutput
 $null=$trafficVoice.Speak($phrases[$phraseIndex])
 $trafficOutput.Close()
}
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($trafficVoice) | Out-Null
