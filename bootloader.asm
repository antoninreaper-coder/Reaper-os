; ========================================
; BOOTLOADER SIMPLE - "Hello World!"
; ========================================
; Ce bootloader affiche "Hello World!" à l'écran
; Architecture : Intel x86 (syntaxe Intel, pas AT&T)
; Taille : 512 octets (requis pour un secteur de boot)
; ========================================

; ORG (ORiGin) indique à l'assembleur où le code sera chargé en mémoire
; Le BIOS charge toujours le bootloader à l'adresse physique 0x7C00
; Toutes les adresses dans le code seront calculées à partir de cette base
[ORG 0x7C00]

; BITS 16 indique que nous sommes en mode réel 16 bits
; Au démarrage, le CPU x86 démarre TOUJOURS en mode réel (compatibilité avec les vieux 8086)
; En mode réel : registres de 16 bits, 1 Mo de RAM accessible
[BITS 16]

; ========================================
; POINT D'ENTRÉE DU BOOTLOADER
; ========================================
start:
    ; ----------------------------------------
    ; INITIALISATION DES REGISTRES DE SEGMENT
    ; ----------------------------------------
    ; En mode réel, l'adressage mémoire utilise la formule : adresse_physique = (segment * 16) + offset
    ; On doit initialiser les segments pour que notre code fonctionne correctement
    
    ; XOR AX, AX : met AX à 0
    ; XOR (eXclusive OR) : opération logique bit à bit
    ; Quand on fait XOR d'une valeur avec elle-même, le résultat est toujours 0
    ; AX est un registre général 16 bits utilisé pour les calculs et transferts
    ; AX = Accumulator register (registre accumulateur)
    ; AX est composé de : AH (8 bits hauts) et AL (8 bits bas)
    xor ax, ax          
    
    ; MOV DS, AX : copie la valeur de AX (0) dans DS
    ; DS = Data Segment (segment de données)
    ; DS pointe vers la zone mémoire où se trouvent nos données (variables, chaînes, etc.)
    ; On ne peut pas faire "mov ds, 0" directement, il faut passer par un registre général
    ; En mettant DS à 0, nos données seront accessibles directement par leur offset
    mov ds, ax          
    
    ; MOV ES, AX : copie la valeur de AX (0) dans ES
    ; ES = Extra Segment (segment supplémentaire)
    ; ES est utilisé pour des opérations sur des chaînes de caractères ou des données supplémentaires
    ; Certaines instructions (comme les opérations de chaînes) utilisent ES par défaut
    mov es, ax          
    
    ; MOV SS, AX : copie la valeur de AX (0) dans SS
    ; SS = Stack Segment (segment de la pile)
    ; SS pointe vers la zone mémoire où se trouve la pile (stack)
    ; La pile sert à sauvegarder temporairement des données (PUSH/POP)
    mov ss, ax          
    
    ; MOV SP, 0x7C00 : initialise le pointeur de pile
    ; SP = Stack Pointer (pointeur de pile)
    ; SP pointe vers le sommet de la pile
    ; La pile grandit VERS LE BAS (de 0x7C00 vers 0x0000)
    ; On met SP juste avant notre bootloader pour ne pas écraser notre code
    ; Quand on fait PUSH, SP diminue ; quand on fait POP, SP augmente
    mov sp, 0x7C00
    
    ; Maintenant que les segments sont initialisés,
    ; on peut accéder à nos données de manière prévisible
    ; Toutes les adresses sont calculées à partir de DS (qui vaut 0)

; ========================================
; AFFICHAGE DU MESSAGE
; ========================================
print_message:
    ; MOV SI, message : charge l'adresse du message dans SI
    ; SI = Source Index (registre d'index source)
    ; SI est un registre 16 bits utilisé pour pointer vers des données en mémoire
    ; Il est souvent utilisé pour parcourir des chaînes de caractères
    ; "message" est une étiquette (label) qui représente l'adresse où commence notre texte
    ; SI va servir de "pointeur" qui se déplace caractère par caractère
    mov si, message
    
; ----------------------------------------
; BOUCLE POUR AFFICHER CHAQUE CARACTÈRE
; ----------------------------------------
; Cette boucle parcourt chaque caractère du message jusqu'au caractère nul (0)
print_loop:
    ; LODSB : Load String Byte
    ; C'est une instruction SPÉCIALE qui fait 3 choses en une seule instruction :
    ; 1. Charge l'octet (byte) pointé par DS:SI dans AL -> 
    ;DS est un gros bloc de mémoire, et SI est un petit bout 
    ;à l'intérieur. DS:SI signifie que l'on cherche SI dans le segment DS.
    ; 2. Incrémente SI de 1 (SI = SI + 1) pour pointer vers le caractère suivant
    ; 3. Tout ça en une seule instruction super rapide !
    ; AL = partie BASSE (8 bits) du registre AX
    ; AL = Accumulator Low (accumulateur bas)
    ; AX est divisé en : AH (8 bits hauts) + AL (8 bits bas)
    ; Exemple : si AX = 0x1234, alors AH = 0x12 et AL = 0x34
    ; AL peut contenir une valeur de 0 à 255 (parfait pour un caractère ASCII)
    lodsb
    
    ; OR AL, AL : fait un OR logique de AL avec lui-même
    ; OR (opération logique OU bit à bit) :
    ; Quand on fait OR d'une valeur avec elle-même, la valeur ne change PAS
    ; MAIS cette instruction met à jour les FLAGS du CPU :
    ; - Zero Flag (ZF) : mis à 1 si le résultat est 0, sinon 0
    ; - Sign Flag (SF) : mis à 1 si le bit de poids fort est 1
    ; On fait ça pour TESTER si AL = 0 sans modifier AL
    ; Si AL = 0, c'est qu'on a atteint la fin de la chaîne (caractère nul)
    or al, al           
    
    ; JZ done : Jump if Zero (sauter si zéro)
    ; JZ = instruction de saut CONDITIONNEL
    ; Elle regarde le Zero Flag (ZF) mis à jour par l'instruction OR précédente
    ; Si ZF = 1 (c'est-à-dire si AL était 0), alors on saute à l'étiquette "done"
    ; Si ZF = 0 (c'est-à-dire si AL contient un caractère), on continue normalement
    ; C'est comme un "if (AL == 0) goto done;" en langage C
    ; "done" est une ÉTIQUETTE (label), pas une instruction de boucle
    ; LODSB n'est PAS un nom de boucle non plus, c'est une instruction normale
    ; La BOUCLE est créée par le JMP à la fin
    jz done
    
    ; Si on arrive ici, c'est que AL contient un caractère valide (différent de 0)
    ; On va maintenant afficher ce caractère à l'écran
    
    ; ----------------------------------------
    ; PRÉPARATION DE L'INTERRUPTION BIOS
    ; ----------------------------------------
    
    ; MOV AH, 0x0E : met la valeur 0x0E dans AH
    ; AH = Accumulator High (partie HAUTE de AX, 8 bits)
    ; AX est composé de AH (bits 8-15) et AL (bits 0-7)
    ; 0x0E = numéro du service "Teletype Output" de l'interruption vidéo
    ; AH sert à indiquer QUEL service on veut utiliser
    ; Service 0x0E = affiche un caractère et avance le curseur automatiquement
    mov ah, 0x0E        
    
    ; AL contient déjà le caractère à afficher (chargé par LODSB)
    ; AL = le caractère ASCII à afficher (par exemple 'H' = 0x48)
    ; On ne touche pas à AL, il a déjà la bonne valeur
    
    ; MOV BH, 0 : met 0 dans BH
    ; BH = partie haute du registre BX
    ; BX = Base register (registre de base, utilisé pour l'adressage)
    ; BH spécifie le NUMÉRO DE PAGE vidéo
    ; En mode texte, on peut avoir plusieurs "pages" d'affichage
    ; Page 0 = la page visible par défaut
    ; On utilise toujours la page 0 pour la simplicité
    mov bh, 0           
    
    ; MOV BL, 0x07 : met 0x07 dans BL
    ; BL = partie basse du registre BX
    ; BL spécifie l'ATTRIBUT DE COULEUR du caractère
    ; 0x07 en binaire : 0000 0111
    ; Bits 0-3 (0111) = couleur du texte = blanc/gris clair
    ; Bits 4-7 (0000) = couleur du fond = noir
    ; 0x07 = texte gris clair sur fond noir (couleur par défaut)
    mov bl, 0x07        
    
    ; INT 0x10 : Interruption logicielle numéro 0x10
    ; INT = INTerrupt (interruption)
    ; Une interruption = appel à une fonction du BIOS
    ; 0x10 = interruption vidéo du BIOS (gestion de l'écran)
    ; Le BIOS regarde AH pour savoir quel service exécuter (0x0E = teletype)
    ; Paramètres utilisés par le service 0x0E :
    ;   - AH = 0x0E (numéro de service)
    ;   - AL = caractère à afficher
    ;   - BH = numéro de page
    ;   - BL = couleur (en mode graphique seulement)
    ; Résultat : le caractère s'affiche à l'écran et le curseur avance
    int 0x10            
    
    ; JMP print_loop : saut INCONDITIONNEL vers l'étiquette print_loop
    ; JMP = JUMP (sauter)
    ; C'est un saut qui se fait TOUJOURS (pas de condition)
    ; On retourne au début de la boucle pour afficher le caractère suivant
    ; C'est cette instruction qui crée la BOUCLE :
    ; print_loop -> lodsb -> or -> jz (si pas 0) -> mov -> int -> jmp -> print_loop...
    ; La boucle continue jusqu'à ce que JZ nous fasse sauter à "done"
    jmp print_loop

; ========================================
; FIN DU PROGRAMME
; ========================================
done:
    ; On arrive ici quand tous les caractères ont été affichés
    ; Le message "Hello World!" est maintenant à l'écran
    ; On doit maintenant arrêter proprement le bootloader
    
    ; CLI : Clear Interrupt flag
    ; CLI = Clear Interrupts (désactiver les interruptions)
    ; Met le flag IF (Interrupt Flag) à 0
    ; Quand IF = 0, le CPU ignore toutes les interruptions matérielles
    ; (sauf les interruptions non-masquables et les exceptions)
    ; On fait ça pour que le CPU ne soit pas dérangé pendant qu'il dort (HLT)
    cli                 
    
    ; HLT : Halt (arrêter/mettre en pause)
    ; Met le processeur en état de BASSE CONSOMMATION
    ; Le CPU arrête d'exécuter des instructions et attend
    ; Il se réveillera seulement si une interruption arrive
    ; Mais comme on a fait CLI, les interruptions sont désactivées
    ; Donc le CPU reste endormi (économise de l'énergie)
    hlt                 
    
    ; JMP done : saut inconditionnel vers l'étiquette "done"
    ; On reboucle ici au cas où :
    ; - Une interruption non-masquable (NMI) réveillerait le CPU
    ; - Une exception (erreur CPU) réveillerait le CPU
    ; Si le CPU se réveille, on le remet en pause immédiatement
    ; Cette boucle infinie empêche le CPU de continuer à exécuter
    ; du code aléatoire qui se trouve après notre bootloader en mémoire
    jmp done            

; ========================================
; DONNÉES
; ========================================
; Cette section contient les données (variables, chaînes, etc.)
; Elle est placée APRÈS le code pour qu'elle ne soit jamais exécutée

message:
    ; DB = Define Byte (définir un ou plusieurs octets)
    ; DB stocke des octets directement en mémoire
    ; 'Hello World!' = chaque lettre est convertie en code ASCII
    ; H = 0x48, e = 0x65, l = 0x6C, l = 0x6C, o = 0x6F, etc.
    ; , 0 = ajoute un octet nul (0x00) à la fin
    ; Le 0 final s'appelle "null terminator" (terminateur nul)
    ; C'est le marqueur de FIN DE CHAÎNE
    ; Notre boucle s'arrête quand elle trouve ce 0
    db 'Hello World!', 0

; ========================================
; REMPLISSAGE ET SIGNATURE DE BOOT
; ========================================
; Un secteur de boot DOIT faire EXACTEMENT 512 octets
; Les 2 derniers octets DOIVENT être 0x55 0xAA (signature magique)
; Sinon le BIOS ne reconnaîtra pas notre code comme bootable

; TIMES 510-($-$$) DB 0 : remplit avec des zéros
; TIMES = répète une instruction N fois
; $ = adresse ACTUELLE (où on est dans le code maintenant)
; $$ = adresse de DÉBUT de la section (0x7C00 dans notre cas)
; $-$$ = nombre d'octets déjà écrits jusqu'ici
; 510-($-$$) = combien d'octets il reste pour arriver à 510
; DB 0 = écrit un octet de valeur 0
; Résultat : on remplit tout l'espace restant avec des zéros
; jusqu'à atteindre l'octet 510 (sur 512)
; Les octets 511 et 512 seront la signature 0xAA55
times 510-($-$$) db 0

; DW 0xAA55 : définit un WORD (mot de 2 octets)
; DW = Define Word (définir un mot de 16 bits)
; 0xAA55 = signature magique du BIOS pour un secteur bootable
; Le BIOS vérifie que les octets 511-512 contiennent cette valeur
; ATTENTION : x86 utilise le format LITTLE-ENDIAN
; Little-endian = l'octet de poids FAIBLE est stocké en premier
; 0xAA55 est stocké en mémoire comme : [0x55] [0xAA]
; Octet 511 = 0x55, Octet 512 = 0xAA
; Si cette signature n'est pas présente, le BIOS dira "No bootable device"
dw 0xAA55

; ========================================
; FIN DU BOOTLOADER
; ========================================
; Total : exactement 512 octets (1 secteur)
; Structure finale :
; - Notre code (quelques dizaines d'octets)
; - Notre message "Hello World!" (13 octets)
; - Des zéros pour remplir (calculé automatiquement)
; - La signature 0xAA55 (2 octets)
; = 512 octets pile poil !
;
; Pour compiler avec NASM :
; nasm -f bin bootloader.asm -o bootloader.bin
; 
; Pour tester avec QEMU :
; qemu-system-x86_64 -drive format=raw,file=bootloader.bin
; 
; Pour tester avec VirtualBox :
; 1. Créer une nouvelle VM
; 2. Utiliser bootloader.bin comme disque de démarrage
; 3. Démarrer la VM
; ========================================
