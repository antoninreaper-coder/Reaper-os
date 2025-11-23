; ========================================
; STAGE 1 BOOTLOADER - Reaper OS
; ========================================
; Ce bootloader est la première étape du chargement de l'OS
; Il est chargé par le BIOS à l'adresse 0x7C00
; Sa mission : charger le stage 2 depuis le disque
; Taille : EXACTEMENT 512 octets (1 secteur)
; ========================================

; ORG 0x7C00 : indique que ce code sera chargé à l'adresse 0x7C00
; Le BIOS charge TOUJOURS le premier secteur à cette adresse
[ORG 0x7C00]

; BITS 16 : on est en mode réel 16 bits (mode du CPU au démarrage)
[BITS 16]

start:
    ; ========================================
    ; INITIALISATION DES SEGMENTS
    ; ========================================
    ; En mode réel, on doit configurer les segments pour accéder à la mémoire
    ; Formule d'adressage : adresse_physique = (segment * 16) + offset
    
    ; CLI = Clear Interrupt flag
    ; On désactive temporairement les interruptions pendant qu'on configure
    ; les segments pour éviter qu'une interruption arrive pendant l'init
    cli
    
    ; XOR AX, AX : met AX à 0 (plus rapide que MOV AX, 0)
    ; XOR avec soi-même donne toujours 0
    xor ax, ax
    
    ; Initialiser tous les segments à 0
    ; DS = Data Segment (pour accéder aux données)
    mov ds, ax
    
    ; ES = Extra Segment (utilisé par certaines instructions de chaîne)
    mov es, ax
    
    ; SS = Stack Segment (pour la pile)
    mov ss, ax
    
    ; SP = Stack Pointer (pointeur de pile)
    ; La pile grandit VERS LE BAS (de 0x7C00 vers 0x0000)
    ; On place SP à 0x7C00 pour que la pile ne déborde pas sur notre code
    mov sp, 0x7C00
    
    ; STI = Set Interrupt flag
    ; Réactiver les interruptions maintenant que tout est configuré
    sti
    
    ; ========================================
    ; SAUVEGARDER LE NUMÉRO DE DRIVE
    ; ========================================
    ; Le BIOS met dans DL le numéro du drive de boot avant de nous lancer
    ; DL = Drive number (0x00 = floppy A, 0x80 = premier disque dur, etc.)
    ; On le sauvegarde à une adresse fixe (0x0500) pour que le stage 2 puisse le récupérer
    ; 0x0500 est une zone de mémoire libre et sûre
    mov [0x0500], dl
    mov [boot_drive], dl
    
    ; ========================================
    ; AFFICHER MESSAGE DE DÉMARRAGE
    ; ========================================
    ; SI = Source Index, utilisé pour pointer vers une chaîne de caractères
    ; On charge l'adresse de notre message de démarrage
    mov si, msg_loading
    
    ; Appeler la fonction qui affiche la chaîne
    call print_string
    
    ; ========================================
    ; CHARGER LE STAGE 2 DEPUIS LE DISQUE
    ; ========================================
    ; Le disque est organisé en secteurs de 512 octets
    ; Secteur 0 = nous (stage 1, le bootloader)
    ; Secteurs 1-5 = stage 2 (notre second bootloader)
    ; Secteurs 6+ = kernel
    
    ; BX = adresse mémoire où charger le stage 2
    ; On le met juste après nous (0x7C00 + 512 = 0x7E00)
    mov bx, 0x7E00
    
    ; DH = nombre de secteurs à lire
    ; Le stage 2 fait environ 2048 octets = 4 secteurs
    ; On charge 5 secteurs pour avoir de la marge
    mov dh, 5
    
    ; DL = numéro du drive (celui qu'on a sauvegardé)
    mov dl, [boot_drive]
    
    ; Appeler la fonction de lecture disque
    call disk_load
    
    ; ========================================
    ; AFFICHER MESSAGE DE SUCCÈS
    ; ========================================
    mov si, msg_success
    call print_string
    
    ; ========================================
    ; TRANSFÉRER LE CONTRÔLE AU STAGE 2
    ; ========================================
    ; Le stage 2 est maintenant en mémoire à l'adresse 0x7E00
    ; On saute à cette adresse pour l'exécuter
    ; JMP = saut inconditionnel (on ne revient jamais ici)
    jmp 0x7E00

; ========================================
; FONCTION : disk_load
; ========================================
; Charge des secteurs depuis le disque en utilisant les services du BIOS
; Cette fonction utilise l'interruption 0x13 (services disque du BIOS)
; 
; PARAMÈTRES D'ENTRÉE :
;   - BX = adresse mémoire de destination (où charger les données)
;   - DH = nombre de secteurs à lire
;   - DL = numéro de drive (0x00 = floppy, 0x80 = HDD, etc.)
; 
; RETOUR :
;   - Rien si succès (les données sont en mémoire à l'adresse BX)
;   - Ne retourne jamais en cas d'erreur (halt du système)
; ========================================
disk_load:
    ; PUSH DX : sauvegarder DX sur la pile
    ; On fait ça car on va modifier DH, mais on a besoin de la valeur
    ; originale plus tard pour vérifier qu'on a bien lu tous les secteurs
    push dx
    
    ; Configuration des paramètres pour l'interruption BIOS 0x13
    ; AH = 0x02 : numéro de la fonction "Read Sectors" du BIOS
    mov ah, 0x02
    
    ; AL = nombre de secteurs à lire (on copie depuis DH)
    mov al, dh
    
    ; CH = numéro de cylindre (bits 0-7)
    ; Un disque dur est organisé en cylindres, têtes et secteurs (CHS)
    ; Cylindre 0 = le premier cylindre (où se trouve le bootloader)
    mov ch, 0
    
    ; CL = numéro de secteur (bits 0-5) + bits 8-9 du cylindre (bits 6-7)
    ; Les secteurs commencent à 1 (pas 0 !)
    ; Secteur 1 = bootloader (nous)
    ; Secteur 2 = début du stage 2
    mov cl, 2
    
    ; DH = numéro de tête (head)
    ; Tête 0 = première surface magnétique du disque
    mov dh, 0
    
    ; DL contient déjà le numéro de drive (passé en paramètre)
    ; ES:BX contient l'adresse de destination (ES=0, BX=0x7E00)
    
    ; INT 0x13 : appeler le service disque du BIOS
    ; Le BIOS va lire les secteurs et les placer en mémoire à ES:BX
    ; Si erreur, le Carry Flag (CF) sera mis à 1
    int 0x13
    
    ; JC = Jump if Carry (sauter si le carry flag est à 1)
    ; Si CF=1, c'est qu'il y a eu une erreur de lecture disque
    jc disk_error
    
    ; POP DX : récupérer la valeur originale de DX depuis la pile
    ; DH contient le nombre de secteurs qu'on voulait lire
    pop dx
    
    ; CMP AL, DH : comparer AL (secteurs lus) avec DH (secteurs demandés)
    ; Après l'int 0x13, AL contient le nombre de secteurs réellement lus
    ; On vérifie qu'on a bien lu tous les secteurs demandés
    cmp al, dh
    
    ; JNE = Jump if Not Equal (sauter si pas égal)
    ; Si AL ≠ DH, on n'a pas lu tous les secteurs → erreur
    jne disk_error
    
    ; RET : retourner à l'appelant
    ; La lecture s'est bien passée, on retourne au code principal
    ret

; ========================================
; GESTION D'ERREUR DISQUE
; ========================================
disk_error:
    ; Afficher un message d'erreur
    mov si, msg_disk_error
    call print_string
    
    ; CLI : désactiver les interruptions
    cli
    
    ; HLT : arrêter le CPU
    ; En cas d'erreur disque, on ne peut pas continuer, donc on s'arrête
    hlt

; ========================================
; FONCTION : print_string
; ========================================
; Affiche une chaîne de caractères terminée par un octet nul (0)
; Utilise la fonction teletype du BIOS (int 0x10, AH=0x0E)
; 
; PARAMÈTRES D'ENTRÉE :
;   - SI = adresse mémoire de la chaîne à afficher
; 
; La chaîne DOIT se terminer par 0, sinon la fonction
; continuera d'afficher des octets aléatoires en mémoire !
; ========================================
print_string:
    ; PUSHA : sauvegarder TOUS les registres généraux sur la pile
    ; (AX, BX, CX, DX, SI, DI, BP, SP)
    ; On fait ça pour que la fonction ne modifie pas les registres
    ; de l'appelant (bonne pratique de programmation)
    pusha
    
.loop:  ; Étiquette locale (le . indique qu'elle appartient à print_string)
    ; LODSB : Load String Byte
    ; Cette instruction magique fait 3 choses en même temps :
    ; 1. Charge l'octet à l'adresse DS:SI dans AL
    ; 2. Incrémente SI de 1 (SI = SI + 1)
    ; 3. Le tout en une seule instruction ultra-rapide
    ; Résultat : AL contient le caractère, SI pointe vers le suivant
    lodsb
    
    ; OR AL, AL : fait un OR logique de AL avec lui-même
    ; Pourquoi ? Pour mettre à jour le Zero Flag (ZF)
    ; Si AL = 0 (fin de chaîne), alors ZF = 1
    ; Si AL ≠ 0 (caractère valide), alors ZF = 0
    ; AL reste inchangé, seuls les flags sont modifiés
    or al, al
    
    ; JZ = Jump if Zero (sauter si ZF = 1)
    ; Si AL était 0, on a atteint la fin de la chaîne → on sort
    jz .done
    
    ; Si on arrive ici, AL contient un caractère à afficher
    
    ; AH = 0x0E : numéro de service "Teletype Output" du BIOS
    ; Ce service affiche un caractère et avance le curseur automatiquement
    mov ah, 0x0E
    
    ; BH = numéro de page vidéo (0 = page par défaut)
    mov bh, 0
    
    ; INT 0x10 : interruption vidéo du BIOS
    ; Le BIOS affiche le caractère contenu dans AL
    int 0x10
    
    ; JMP .loop : retourner au début de la boucle
    ; On continue à afficher les caractères jusqu'à trouver un 0
    jmp .loop
    
.done:  ; On arrive ici quand toute la chaîne a été affichée
    ; POPA : restaurer tous les registres depuis la pile
    ; On remet les registres dans l'état où ils étaient avant l'appel
    popa
    
    ; RET : retourner à l'appelant
    ret

; ========================================
; DONNÉES
; ========================================
; Ces chaînes sont stockées directement dans le code du bootloader
; Elles sont en mémoire et accessibles via leurs étiquettes (labels)

; Message affiché au démarrage
; 13 = Carriage Return (retour chariot, début de ligne)
; 10 = Line Feed (nouvelle ligne)
; 0 = null terminator (fin de chaîne)
msg_loading:     db 'Reaper OS - Loading Stage 2...', 13, 10, 0

; Message après chargement réussi
msg_success:     db 'Stage 2 loaded!', 13, 10, 0

; Message d'erreur si le disque ne répond pas
msg_disk_error:  db 'Disk read error!', 13, 10, 0

; Variable pour stocker le numéro de drive
; DB 0 = Define Byte, réserve 1 octet initialisé à 0
boot_drive:      db 0

; ========================================
; REMPLISSAGE ET SIGNATURE DE BOOT
; ========================================
; Un secteur de boot DOIT faire EXACTEMENT 512 octets
; Les 2 derniers octets DOIVENT être 0x55 0xAA (signature magique)

; TIMES 510-($-$$) DB 0 : remplir avec des zéros
; $ = adresse actuelle (où on est maintenant dans le code)
; $$ = adresse de début de section (0x7C00)
; $-$$ = nombre d'octets déjà écrits
; 510-($-$$) = combien d'octets manquent pour arriver à 510
; On remplit l'espace restant avec des 0 jusqu'à l'octet 510
times 510-($-$$) db 0

; DW 0xAA55 : Define Word (2 octets)
; 0xAA55 = signature magique que le BIOS cherche
; Si les 2 derniers octets d'un secteur = 0xAA55,
; alors le BIOS considère ce secteur comme bootable
; ATTENTION : x86 est little-endian, donc 0xAA55 est stocké comme [55 AA]
; Octet 511 = 0x55, Octet 512 = 0xAA
dw 0xAA55

; ========================================
; FIN DU STAGE 1 BOOTLOADER
; ========================================
; Total : EXACTEMENT 512 octets
; Le BIOS charge ce code à 0x7C00 et l'exécute
; Ce code charge ensuite le stage 2 et lui passe le contrôle
; ========================================
