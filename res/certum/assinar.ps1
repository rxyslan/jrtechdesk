# Assina arquivos do JrTechDesk com o certificado Certum (SimplySign já logado por auth.mjs
# e certificado localizado por verify.ps1, que definem CERTUM_CERT_THUMBPRINT,
# CERTUM_CERT_SUBJECT e CERTUM_SIGNTOOL_PATH).
#
#   assinar.ps1 -Pasta ./rustdesk -SoSemAssinatura   arquivos internos (.exe e .dll)
#   assinar.ps1 -Arquivos a.exe,b.msi                 instalador e .msi
#
# -SoSemAssinatura pula o que já tem assinatura válida de outro editor (bibliotecas da
# Microsoft, por exemplo) e os drivers de terceiros, que já vêm assinados.

[CmdletBinding()]
param(
    [string]$Pasta,
    [string[]]$Arquivos,
    [switch]$SoSemAssinatura
)

$ErrorActionPreference = 'Stop'

$thumb = $env:CERTUM_CERT_THUMBPRINT
$subject = $env:CERTUM_CERT_SUBJECT
$signtool = $env:CERTUM_SIGNTOOL_PATH
if (-not $thumb -or -not $signtool) {
    throw "Certificado ou signtool não localizados (rode verify.ps1 antes)."
}
# Só assina com o certificado da empresa, nunca com outro que esteja na conta.
if ($subject -notmatch 'Jrtech') {
    throw "O certificado localizado não é da Jrtech: $subject"
}

$alvos = @()
if ($Pasta) {
    $alvos += Get-ChildItem -LiteralPath $Pasta -Recurse -File |
        Where-Object { $_.Extension -in '.exe', '.dll' -and $_.FullName -notmatch 'RustDeskPrinterDriver|usbmmidd_v2' }
}
if ($Arquivos) {
    $alvos += $Arquivos | ForEach-Object { Get-Item -LiteralPath $_ }
}
if ($SoSemAssinatura) {
    $alvos = $alvos | Where-Object { (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid' }
}
$alvos = @($alvos)
if ($alvos.Count -eq 0) {
    Write-Host "Nada a assinar."
    exit 0
}

Write-Host "Assinando $($alvos.Count) arquivo(s) com $subject ($thumb)"
foreach ($f in $alvos) {
    $ok = $false
    # O servidor de carimbo de tempo às vezes falha; tenta de novo antes de desistir.
    for ($i = 1; $i -le 4 -and -not $ok; $i++) {
        & $signtool sign /sha1 $thumb /fd SHA256 /tr http://time.certum.pl /td SHA256 /q $f.FullName
        if ($LASTEXITCODE -eq 0) {
            $ok = $true
        } else {
            Write-Warning "Falha ao assinar $($f.Name) (tentativa $i); tentando de novo em $($i * 5) s"
            Start-Sleep -Seconds ($i * 5)
        }
    }
    if (-not $ok) { throw "Não foi possível assinar $($f.FullName)" }

    $sig = Get-AuthenticodeSignature -LiteralPath $f.FullName
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Thumbprint -ne $thumb -or -not $sig.TimeStamperCertificate) {
        throw "Assinatura de $($f.FullName) não conferiu: $($sig.Status)"
    }
    Write-Host "  ok  $($f.Name)"
}
