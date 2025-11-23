; ========================================
; STAGE 2 BOOTLOADER - Reaper OS
; ========================================
; Ce bootloader est chargé par le stage 1
; Il tourne à l'adresse 0x7E00
; Sa mission : charger le kernel et passer en mode protégé 32-bit
; Taille : environ 2048 octets (4 secteurs)
; ========================================

[ORG 0x7E00]
[BITS 16]

start_stage2:
    ; ========================================
    ; AFFICHER MESSAGE DE DÉMARRAGE STAGE 2
    ; ========================================
    mov si, msg_stage2
    call print_string
    
    ; ========================================
    ; CHARGER LE KERNEL DEPUIS LE DISQUE
    ; ========================================
    ; Le kernel est stocké après le stage 2 sur le disque
    ; Organisation du disque :
    ; - Secteur 1 : stage 1 (bootloader principal)
    ; - Secteurs 2-6 : stage 2 (nous)
    ; - Secteurs 7+ : kernel
    
    ; BX = adresse où charger le kernel
    ; On le charge à 0x1000 (4096 en décimal)
    ; C'est une zone sûre de la mémoire, loin de nos bootloaders
    mov bx, 0x1000
    
    ; DH = nombre de secteurs du kernel à lire
    ; Le kernel fait environ 10KB = 20 secteurs
    mov dh, 20
    
    ; DL = numéro de drive (récupéré depuis le stage 1)
    ; Le stage 1 a sauvegardé le numéro de drive à l'adresse fixe 0x0500
    mov dl, [0x0500]
    
    ; CL = secteur de départ
    ; Le kernel commence au secteur 7 (après le stage 2)
    ; Secteur 1 = stage 1, secteurs 2-5 = stage 2, secteur 6+ = kernel
    mov cl, 7
    
    ; Charger le kernel
    call disk_load_kernel
    
    ; ========================================
    ; AFFICHER MESSAGE DE SUCCÈS
    ; ========================================
    mov si, msg_kernel_loaded
    call print_string
    
    ; ========================================
    ; PRÉPARER LE PASSAGE EN MODE PROTÉGÉ
    ; ========================================
    ; Le mode protégé est le mode 32-bit du processeur
    ; Il permet d'accéder à toute la RAM (pas limité à 1 MB)
    ; Il offre la protection mémoire, les privilèges, etc.
    
    ; CLI : désactiver les interruptions
    ; IMPORTANT : les interruptions du BIOS ne fonctionnent qu'en mode réel
    ; En mode protégé, il faudra créer nos propres gestionnaires d'interruptions
    cli
    
    ; LGDT : Load Global Descriptor Table
    ; La GDT définit les segments mémoire en mode protégé
    ; [gdt_descriptor] contient l'adresse et la taille de notre GDT
    lgdt [gdt_descriptor]
    
    ; ========================================
    ; ACTIVER LE MODE PROTÉGÉ
    ; ========================================
    ; Pour activer le mode protégé, on doit mettre le bit 0 du registre CR0 à 1
    ; CR0 = Control Register 0 (registre de contrôle du CPU)
    
    ; MOV EAX, CR0 : copier CR0 dans EAX
    ; On ne peut pas modifier CR0 directement, il faut passer par un registre
    mov eax, cr0
    
    ; OR EAX, 1 : mettre le bit 0 de EAX à 1
    ; Bit 0 de CR0 = PE (Protection Enable)
    ; PE = 1 → mode protégé activé
    or eax, 1
    
    ; MOV CR0, EAX : recopier EAX dans CR0
    ; À partir de maintenant, le CPU est en mode protégé !
    mov cr0, eax
    
    ; ========================================
    ; FAR JUMP POUR VIDER LE PIPELINE
    ; ========================================
    ; Après avoir activé le mode protégé, le pipeline du CPU contient
    ; encore des instructions 16-bit. On doit le vider avec un far jump.
    ; Un far jump charge aussi le segment de code (CS) avec notre nouveau sélecteur
    
    ; JMP CODE_SEG:start_protected_mode
    ; CODE_SEG = sélecteur du segment de code dans la GDT (0x08)
    ; start_protected_mode = adresse où continuer en mode protégé 32-bit
    jmp CODE_SEG:start_protected_mode

; ========================================
; FONCTION : disk_load_kernel
; ========================================
; Charge le kernel depuis le disque (similaire au stage 1)
; 
; PARAMÈTRES :
;   - BX = adresse de destination
;   - DH = nombre de secteurs
;   - DL = numéro de drive
;   - CL = secteur de départ
; ========================================
disk_load_kernel:
    ; Sauvegarder DX pour vérification ultérieure
    push dx
    
    ; AH = 0x02 : fonction "Read Sectors" du BIOS
    mov ah, 0x02
    
    ; AL = nombre de secteurs à lire
    mov al, dh
    
    ; CH = cylindre 0
    mov ch, 0
    
    ; CL contient déjà le secteur de départ (passé en paramètre)
    
    ; DH = tête 0
    mov dh, 0
    
    ; DL contient déjà le numéro de drive
    
    ; INT 0x13 : lire les secteurs
    int 0x13
    
    ; Vérifier les erreurs (carry flag)
    jc disk_error_stage2
    
    ; Récupérer le nombre de secteurs demandés
    pop dx
    
    ; Vérifier qu'on a lu tous les secteurs
    ; AL contient le nombre de secteurs réellement lus
    ; DH contient le nombre de secteurs demandés
    cmp al, dh
    jne disk_error_stage2
    
    ret

; ========================================
; GESTION D'ERREUR (MODE RÉEL)
; ========================================
disk_error_stage2:
    mov si, msg_disk_error_s2
    call print_string
    cli
    hlt

; ========================================
; FONCTION : print_string (MODE RÉEL)
; ========================================
; Identique à celle du stage 1
; Affiche une chaîne en mode réel avec le BIOS
; ========================================
print_string:
    pusha
.loop:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0
    int 0x10
    jmp .loop
.done:
    popa
    ret

; ========================================
; MODE PROTÉGÉ 32-BIT
; ========================================
; À partir d'ici, on est en mode protégé
; Plus d'accès au BIOS !
; Les registres sont maintenant 32-bit (EAX, EBX, etc.)
; ========================================

[BITS 32]

start_protected_mode:
    ; ========================================
    ; INITIALISER LES SEGMENTS EN MODE PROTÉGÉ
    ; ========================================
    ; En mode protégé, les registres de segment contiennent des SÉLECTEURS
    ; qui pointent vers des entrées dans la GDT
    
    ; AX = DATA_SEG (0x10 = sélecteur du segment de données dans la GDT)
    mov ax, DATA_SEG
    
    ; Tous les segments de données pointent vers le même descripteur
    ; DS = Data Segment
    mov ds, ax
    
    ; ES = Extra Segment
    mov es, ax
    
    ; FS = segment supplémentaire (utilisé par certains OS pour des données spéciales)
    mov fs, ax
    
    ; GS = segment supplémentaire
    mov gs, ax
    
    ; SS = Stack Segment
    mov ss, ax
    
    ; ESP = Extended Stack Pointer (pointeur de pile 32-bit)
    ; On place la pile en haut de la mémoire libre (0x90000 = 576 KB)
    ; C'est une zone sûre, loin de notre code
    mov esp, 0x90000
    
    ; ========================================
    ; AFFICHER MESSAGE EN MODE PROTÉGÉ
    ; ========================================
    ; En mode protégé, on ne peut plus utiliser le BIOS (int 0x10)
    ; On doit écrire directement dans la mémoire vidéo
    ; La mémoire vidéo texte est à l'adresse 0xB8000
    
    ; EBX = adresse du message
    mov ebx, msg_protected
    
    ; Appeler notre fonction d'affichage pour le mode protégé
    call print_string_pm
    
    ; ========================================
    ; SAUTER AU KERNEL
    ; ========================================
    ; Le kernel est chargé à l'adresse 0x1000
    jmp 0x1000

; ========================================
; FONCTION : print_string_pm
; ========================================
; Affiche une chaîne en mode protégé
; Écrit directement dans la mémoire vidéo (VGA text mode)
; 
; MÉMOIRE VIDÉO :
; - Adresse de base : 0xB8000
; - Format : 80 colonnes x 25 lignes
; - Chaque caractère = 2 octets :
;   * Octet 1 : code ASCII du caractère
;   * Octet 2 : attribut de couleur (4 bits fond + 4 bits texte)
; 
; PARAMÈTRES :
;   - EBX = adresse de la chaîne (terminée par 0)
; ========================================
print_string_pm:
    ; Sauvegarder tous les registres
    pusha
    
    ; EDX = adresse de la mémoire vidéo
    mov edx, 0xB8000
    
    ; On commence à la ligne 3 (2 lignes * 160 octets)
    ; 160 = 80 caractères * 2 octets par caractère
    add edx, 160 * 2
    
.loop:
    ; AL = caractère à afficher
    mov al, [ebx]
    
    ; AH = attribut de couleur
    ; 0x0F = texte blanc (15) sur fond noir (0)
    ; Format : 0000 (fond noir) 1111 (texte blanc)
    mov ah, 0x0F
    
    ; Vérifier si on a atteint la fin de la chaîne
    cmp al, 0
    je .done
    
    ; Écrire le caractère + attribut dans la mémoire vidéo
    ; [EDX] = AX (2 octets : caractère + couleur)
    mov [edx], ax
    
    ; Passer au caractère suivant dans la chaîne
    add ebx, 1
    
    ; Passer à la position suivante à l'écran (2 octets plus loin)
    add edx, 2
    
    ; Continuer la boucle
    jmp .loop
    
.done:
    ; Restaurer les registres
    popa
    ret

; ========================================
; GDT (Global Descriptor Table)
; ========================================
; La GDT définit les segments mémoire en mode protégé
; Chaque entrée (descripteur) fait 8 octets et décrit un segment :
; - Sa base (adresse de départ)
; - Sa limite (taille)
; - Ses attributs (type, privilèges, etc.)
; ========================================

gdt_start:
    ; ========================================
    ; DESCRIPTEUR NULL (obligatoire)
    ; ========================================
    ; Le premier descripteur DOIT être nul
    ; C'est une sécurité : si on utilise le sélecteur 0, ça génère une erreur
    dq 0x0  ; DQ = Define Quad-word (8 octets)

gdt_code:
    ; ========================================
    ; DESCRIPTEUR DE SEGMENT DE CODE
    ; ========================================
    ; Ce segment contient le code exécutable
    
    ; LIMITE (bits 0-15) : 0xFFFF
    ; La limite définit la taille maximale du segment
    ; 0xFFFF = 65535 en mode 16-bit, mais avec granularité 4K ça donne 4 GB
    dw 0xFFFF
    
    ; BASE (bits 0-15) : 0x0
    ; La base est l'adresse de départ du segment
    ; 0x0 = le segment commence à l'adresse 0 (tout le début de la RAM)
    dw 0x0
    
    ; BASE (bits 16-23) : 0x0
    db 0x0
    
    ; FLAGS D'ACCÈS : 10011010b
    ; Bit 7 (P) : 1 = Present (segment présent en mémoire)
    ; Bits 5-6 (DPL) : 00 = ring 0 (privilège maximum, kernel)
    ; Bit 4 (S) : 1 = segment de code/données (pas système)
    ; Bit 3 (E) : 1 = Executable (c'est du code)
    ; Bit 2 (DC) : 0 = Direction/Conforming
    ; Bit 1 (RW) : 1 = Readable (le code peut être lu)
    ; Bit 0 (A) : 0 = Accessed (mis à 1 par le CPU quand utilisé)
    db 10011010b
    
    ; FLAGS + LIMITE (bits 16-19) : 11001111b
    ; Bit 7 (G) : 1 = Granularité 4K (la limite est en pages de 4 KB)
    ; Bit 6 (D/B) : 1 = 32-bit segment (opérations 32-bit par défaut)
    ; Bit 5 (L) : 0 = pas en mode 64-bit
    ; Bit 4 (AVL) : 0 = disponible pour l'OS
    ; Bits 0-3 : 1111 = bits 16-19 de la limite
    db 11001111b
    
    ; BASE (bits 24-31) : 0x0
    db 0x0

gdt_data:
    ; ========================================
    ; DESCRIPTEUR DE SEGMENT DE DONNÉES
    ; ========================================
    ; Ce segment contient les données (variables, pile, etc.)
    ; Quasiment identique au segment de code, sauf qu'il n'est pas exécutable
    
    dw 0xFFFF       ; Limite (bits 0-15)
    dw 0x0          ; Base (bits 0-15)
    db 0x0          ; Base (bits 16-23)
    
    ; FLAGS D'ACCÈS : 10010010b
    ; La seule différence avec le code : bit 3 (E) = 0 (non exécutable)
    ; Bit 1 (RW) = 1 signifie ici "Writable" (on peut écrire dedans)
    db 10010010b
    
    db 11001111b    ; Flags + limite (bits 16-19)
    db 0x0          ; Base (bits 24-31)

gdt_end:
    ; Marque la fin de la GDT

; ========================================
; DESCRIPTEUR DE LA GDT
; ========================================
; Cette structure de 6 octets est utilisée par l'instruction LGDT
; Elle indique au CPU où se trouve la GDT et quelle est sa taille
; ========================================
gdt_descriptor:
    ; Taille de la GDT - 1 (2 octets)
    ; On soustrait 1 car c'est comme ça que le CPU veut la taille
    dw gdt_end - gdt_start - 1
    
    ; Adresse de la GDT (4 octets en mode 32-bit)
    dd gdt_start

; ========================================
; CONSTANTES POUR LES SÉLECTEURS
; ========================================
; Un sélecteur est un index dans la GDT
; Format : index * 8 (car chaque descripteur fait 8 octets)
; 
; CODE_SEG = offset du descripteur de code dans la GDT
; gdt_code est à 8 octets du début (après le descripteur null)
; Donc CODE_SEG = 0x08
CODE_SEG equ gdt_code - gdt_start

; DATA_SEG = offset du descripteur de données dans la GDT
; gdt_data est à 16 octets du début
; Donc DATA_SEG = 0x10
DATA_SEG equ gdt_data - gdt_start

; ========================================
; DONNÉES
; ========================================
msg_stage2:          db 'Stage 2 running...', 13, 10, 0
msg_kernel_loaded:   db 'Kernel loaded, entering protected mode...', 13, 10, 0
msg_disk_error_s2:   db 'Stage 2: Disk error!', 13, 10, 0
msg_protected:       db 'Protected mode active!', 0

; Remplissage pour occuper plusieurs secteurs
; On remplit jusqu'à 2048 octets (4 secteurs)
times 2048-($-$$) db 0

; ========================================
; FIN DU STAGE 2 BOOTLOADER
; ========================================
; Ce bootloader a chargé le kernel et activé le mode protégé
; Le contrôle est maintenant passé au kernel qui va initialiser l'OS
; ========================================
