# ========================================
# Script de compilation - Reaper OS
# ========================================
# Ce script PowerShell automatise la compilation de tous les composants de l'OS
# et assemble l'image disque bootable finale
#
# ÉTAPES :
# 1. Compiler les 3 fichiers ASM (stage1, stage2, kernel) avec NASM
# 2. Créer une image disque vide de 1.44 MB (taille d'une disquette)
# 3. Copier les binaires aux bons emplacements dans l'image
# 4. Afficher un résumé et les instructions pour tester
#
# PRÉREQUIS :
# - NASM installé et dans le PATH
# - PowerShell 5.1 ou supérieur
# ========================================

Write-Host "=== Compilation de Reaper OS ===" -ForegroundColor Green

# ========================================
# ÉTAPE 1 : COMPILER LE STAGE 1 (BOOTLOADER)
# ========================================
# Le stage 1 est le premier code exécuté par le BIOS
# Il fait exactement 512 octets et contient la signature 0xAA55
# Sa fonction : charger le stage 2 depuis le disque
Write-Host "Compilation du Stage 1..." -ForegroundColor Cyan

# NASM : Netwide Assembler
# -f bin : format de sortie binaire brut (pas d'en-têtes ELF/PE)
# -o : fichier de sortie
nasm -f bin boot_stage1.asm -o boot_stage1.bin
nasm -f bin boot_stage1.asm -o boot_stage1.bin

# $LASTEXITCODE : variable automatique contenant le code de retour de la dernière commande
# 0 = succès, autre = erreur
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erreur lors de la compilation du Stage 1!" -ForegroundColor Red
    exit 1  # Arrêter le script avec un code d'erreur
}

# ========================================
# ÉTAPE 2 : COMPILER LE STAGE 2
# ========================================
# Le stage 2 est plus gros (~2048 octets)
# Il charge le kernel et active le mode protégé 32-bit
Write-Host "Compilation du Stage 2..." -ForegroundColor Cyan
nasm -f bin boot_stage2.asm -o boot_stage2.bin
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erreur lors de la compilation du Stage 2!" -ForegroundColor Red
    exit 1
}

# ========================================
# ÉTAPE 3 : COMPILER LE KERNEL
# ========================================
# Le kernel contient le code principal de l'OS
# Il tourne en mode protégé et gère l'affichage et le clavier
Write-Host "Compilation du Kernel..." -ForegroundColor Cyan
nasm -f bin kernel.asm -o kernel.bin
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erreur lors de la compilation du Kernel!" -ForegroundColor Red
    exit 1
}

# ========================================
# ÉTAPE 4 : CRÉER L'IMAGE DISQUE
# ========================================
# Une image disque est un fichier qui représente un disque entier
# On va créer une image de 1.44 MB (taille d'une disquette 3.5")
Write-Host "Creation de l'image disque..." -ForegroundColor Cyan

# Taille d'une disquette : 1474560 octets = 1.44 MB = 2880 secteurs de 512 octets
$diskSize = 1474560

# Créer un tableau d'octets rempli de zéros
# C'est notre disque virtuel vide
$zeros = New-Object byte[] $diskSize

# Écrire ce tableau dans un fichier
# $PWD = répertoire de travail actuel (Present Working Directory)
[System.IO.File]::WriteAllBytes("$PWD\reaper_os.img", $zeros)

# ========================================
# ÉTAPE 5 : CHARGER LES BINAIRES
# ========================================
# Lire les 3 fichiers compilés en mémoire
# ReadAllBytes retourne un tableau d'octets
$stage1 = [System.IO.File]::ReadAllBytes("$PWD\boot_stage1.bin")
$stage2 = [System.IO.File]::ReadAllBytes("$PWD\boot_stage2.bin")
$kernel = [System.IO.File]::ReadAllBytes("$PWD\kernel.bin")

# ========================================
# ÉTAPE 6 : ASSEMBLER L'IMAGE DISQUE
# ========================================
# On va copier les binaires aux bons endroits dans l'image disque
# Organisation du disque :
#   Secteur 0 (offset 0) : Stage 1 (bootloader, 512 octets)
#   Secteur 1-5 (offset 512) : Stage 2 (~2048 octets)
#   Secteur 6+ (offset 3072) : Kernel (~10 KB)

# Ouvrir l'image disque en mode écriture
$img = [System.IO.File]::Open("$PWD\reaper_os.img", [System.IO.FileMode]::Open)

# ========================================
# COPIER LE STAGE 1 AU SECTEUR 0
# ========================================
# Seek = se positionner à un offset dans le fichier
# Offset 0 = tout début du fichier = secteur 0
$img.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null

# Write = écrire des octets dans le fichier
# Paramètres : (tableau source, index de départ, nombre d'octets)
$img.Write($stage1, 0, $stage1.Length)

# ========================================
# COPIER LE STAGE 2 AU SECTEUR 1
# ========================================
# Offset 512 = début du secteur 1 (512 octets = 1 secteur)
$img.Seek(512, [System.IO.SeekOrigin]::Begin) | Out-Null
$img.Write($stage2, 0, $stage2.Length)

# ========================================
# COPIER LE KERNEL AU SECTEUR 7
# ========================================
# Offset 3584 = début du secteur 7
# Calcul : 7 secteurs * 512 octets = 3584
# Secteur 1 = stage 1
# Secteurs 2-6 = stage 2 (on lui donne 5 secteurs)
# Secteur 7+ = kernel
$img.Seek(3584, [System.IO.SeekOrigin]::Begin) | Out-Null
$img.Write($kernel, 0, $kernel.Length)

# Fermer le fichier (important pour sauvegarder les changements)
$img.Close()

# ========================================
# AFFICHER LE RÉSUMÉ
# ========================================
Write-Host "`n=== Compilation terminee avec succes! ===" -ForegroundColor Green

# `n = nouvelle ligne dans une chaîne PowerShell
Write-Host "`nFichiers crees:" -ForegroundColor Yellow

# $($variable.Length) = interpolation pour afficher la taille
Write-Host "  - boot_stage1.bin ($($stage1.Length) octets)" -ForegroundColor White
Write-Host "  - boot_stage2.bin ($($stage2.Length) octets)" -ForegroundColor White
Write-Host "  - kernel.bin ($($kernel.Length) octets)" -ForegroundColor White
Write-Host "  - reaper_os.img (1.44 MB)" -ForegroundColor White

# ========================================
# INSTRUCTIONS POUR TESTER
# ========================================
Write-Host "`nPour tester avec QEMU:" -ForegroundColor Cyan

# Commande à copier-coller pour lancer l'OS dans QEMU
# -drive format=raw,file=... : utilise l'image disque comme disque dur
Write-Host '  qemu-system-x86_64 -drive format=raw,file=reaper_os.img' -ForegroundColor White

# ========================================
# FIN DU SCRIPT
# ========================================
# L'image disque reaper_os.img est maintenant prête
# Elle peut être :
#   - Testée dans QEMU (émulateur)
#   - Testée dans VirtualBox (machine virtuelle)
#   - Écrite sur une vraie disquette ou clé USB (avec dd sous Linux)
# ========================================
