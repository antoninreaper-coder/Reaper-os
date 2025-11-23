; ========================================
; KERNEL MINIMALISTE - Reaper OS
; ========================================
; 
; QU'EST-CE QU'UN KERNEL ?
; ------------------------
; Le kernel (noyau) est le cœur d'un système d'exploitation.
; C'est le premier programme qui s'exécute après le bootloader.
; Il gère :
;   - La mémoire (RAM)
;   - Le processeur (CPU)
;   - Les périphériques (clavier, disque, écran, etc.)
;   - Les programmes (processus)
; 
; NOTRE KERNEL :
; --------------
; Ce kernel est TRÈS minimaliste, mais il est un vrai kernel !
; Il tourne en mode protégé 32-bit (comme Windows, Linux, etc.)
; Il est chargé à l'adresse 0x1000 (4096 en décimal) par le stage 2
; 
; FONCTIONNALITÉS :
; -----------------
;   - Affichage de texte coloré directement à l'écran
;   - Lecture du clavier (touches H, C, R)
;   - Commandes interactives :
;     * H = Help (afficher l'aide)
;     * C = Clear (effacer l'écran)
;     * R = Reboot (redémarrer l'ordinateur)
; 
; ARCHITECTURE :
; --------------
; 1. Initialisation (effacer l'écran, afficher l'interface)
; 2. Boucle principale (attendre une touche, exécuter la commande)
; 3. Fonctions utilitaires (affichage, clavier)
; 4. Données (messages, variables)
; 
; ========================================

; [BITS 32] : indique à l'assembleur qu'on est en mode 32-bit
; Toutes les instructions et adresses seront sur 32 bits
; Les registres sont EAX, EBX, ECX, EDX... (le E signifie Extended = étendu à 32 bits)
[BITS 32]

; ========================================
; CONSTANTES DE COULEURS
; ========================================
; 
; COMMENT FONCTIONNENT LES COULEURS EN MODE TEXTE ?
; --------------------------------------------------
; En mode texte VGA, chaque caractère à l'écran occupe 2 octets en mémoire :
;   - Octet 1 : le code ASCII du caractère (65 = 'A', 72 = 'H', etc.)
;   - Octet 2 : l'attribut de couleur (fond + texte)
; 
; FORMAT DE L'ATTRIBUT (8 bits) :
; --------------------------------
;   Bit 7 : Clignotement (0 = fixe, 1 = clignotant)
;   Bits 6-4 : Couleur de fond (0-7, 8 couleurs)
;   Bits 3-0 : Couleur du texte (0-15, 16 couleurs)
; 
; PALETTE DE COULEURS :
; ---------------------
;   0 = Noir          8 = Gris foncé
;   1 = Bleu          9 = Bleu clair
;   2 = Vert          A = Vert clair
;   3 = Cyan          B = Cyan clair
;   4 = Rouge         C = Rouge clair
;   5 = Magenta       D = Magenta clair
;   6 = Brun          E = Jaune
;   7 = Gris clair    F = Blanc
; 
; EXEMPLES :
; ----------
;   0x0F = 00001111 = fond noir (0), texte blanc (15)
;   0x1E = 00011110 = fond bleu (1), texte jaune (14)
;   0x4A = 01001010 = fond rouge (4), texte vert clair (10)
; 
; ========================================

; EQU = EQUate (égaler, définir une constante)
; C'est comme un #define en C : ça crée un alias pour une valeur

; Adresse de la mémoire vidéo en mode texte VGA
; C'est à cette adresse que se trouve l'écran (80x25 caractères)
VIDEO_MEMORY    equ 0xB8000

; Attributs de couleur pré-définis (format : fond + texte)
WHITE_ON_BLACK  equ 0x0F            ; Blanc sur noir (classique)
GREEN_ON_BLACK  equ 0x0A            ; Vert clair sur noir (style Matrix)
BLUE_ON_BLACK   equ 0x09            ; Bleu clair sur noir (style info)
RED_ON_BLACK    equ 0x0C            ; Rouge clair sur noir (style erreur)

; ========================================
; POINT D'ENTRÉE DU KERNEL
; ========================================
; 
; Le bootloader (stage 2) saute ici avec JMP 0x1000
; C'est la toute première instruction du kernel qui s'exécute
; 
; À CE MOMENT :
; -------------
;   - Le CPU est en mode protégé 32-bit
;   - La GDT (Global Descriptor Table) est chargée
;   - Les segments sont configurés (CS, DS, ES, SS)
;   - La pile (stack) est à 0x90000
;   - Les interruptions BIOS ne fonctionnent plus !
; 
; ========================================
kernel_start:
    ; ========================================
    ; ÉTAPE 1 : POSITION-INDEPENDENT CODE (PIC)
    ; ========================================
    ; 
    ; PROBLÈME :
    ; ----------
    ; Notre code est chargé à l'adresse 0x1000, mais l'assembleur
    ; ne le sait pas (on n'a pas mis [ORG 0x1000]).
    ; Du coup, quand on écrit "mov esi, msg_title", l'assembleur
    ; met l'OFFSET de msg_title depuis le début du fichier,
    ; pas son adresse ABSOLUE en mémoire.
    ; 
    ; SOLUTION :
    ; ----------
    ; On utilise une technique appelée "position-independent code".
    ; On fait un CALL suivi d'un POP pour obtenir notre adresse réelle.
    ; 
    ; FONCTIONNEMENT :
    ; ----------------
    ; 1. CALL .get_base
    ;    → Le CPU empile (PUSH) l'adresse de retour (l'adresse de POP EBX)
    ;    → Le CPU saute à .get_base
    ; 2. POP EBX
    ;    → On récupère l'adresse de retour qu'on vient d'empiler
    ;    → EBX contient maintenant l'adresse RÉELLE de cette instruction
    ; 3. SUB EBX, (.get_base - kernel_start)
    ;    → On soustrait l'offset de .get_base depuis le début
    ;    → EBX contient maintenant l'adresse de kernel_start en mémoire (0x1000)
    ; 
    ; RÉSULTAT :
    ; ----------
    ; EBX = 0x1000 = adresse de base du kernel
    ; On peut maintenant calculer l'adresse absolue de n'importe quel label :
    ;   adresse_absolue = EBX + (label - kernel_start)
    ; 
    call .get_base              ; Empiler l'adresse de retour et sauter
.get_base:
    pop ebx                     ; EBX = adresse de cette instruction
    sub ebx, (.get_base - kernel_start)  ; EBX = adresse de kernel_start
    mov [kernel_base], ebx      ; Sauvegarder pour usage ultérieur dans la boucle
    
    ; ========================================
    ; ÉTAPE 2 : CONFIGURER LA DIRECTION DES CHAÎNES
    ; ========================================
    ; 
    ; QU'EST-CE QUE DF (Direction Flag) ?
    ; ------------------------------------
    ; Le CPU a un flag appelé DF qui contrôle la direction des opérations
    ; sur les chaînes (LODSB, STOSB, MOVSB, etc.).
    ; 
    ; - DF = 0 : les opérations progressent vers le HAUT (adresses croissantes)
    ;            SI/DI s'incrémentent automatiquement
    ; - DF = 1 : les opérations progressent vers le BAS (adresses décroissantes)
    ;            SI/DI se décrémentent automatiquement
    ; 
    ; INSTRUCTIONS :
    ; --------------
    ; - CLD (CLear Direction flag) : met DF à 0
    ; - STD (SeT Direction flag) : met DF à 1
    ; 
    ; POURQUOI CLD ICI ?
    ; ------------------
    ; On veut que nos chaînes se lisent de gauche à droite (normale),
    ; donc on s'assure que DF = 0.
    ; 
    cld                         ; DF = 0 (direction avant)
    
    ; ========================================
    ; ÉTAPE 3 : EFFACER L'ÉCRAN
    ; ========================================
    ; 
    ; L'ÉCRAN EN MODE TEXTE :
    ; -----------------------
    ; - Résolution : 80 colonnes x 25 lignes = 2000 caractères
    ; - Mémoire : 2000 caractères * 2 octets = 4000 octets
    ; - Adresse de départ : 0xB8000
    ; - Adresse de fin : 0xB8000 + 4000 = 0xB8FA0
    ; 
    ; COMMENT ON EFFACE ?
    ; -------------------
    ; On remplit toute la mémoire vidéo avec des espaces blancs.
    ; On utilise l'instruction REP STOSW :
    ;   - STOSW : STOre String Word (écrire AX à [EDI] puis EDI += 2)
    ;   - REP : REPeat (répéter ECX fois)
    ; 
    ; PRÉPARATION :
    ; -------------
    ; EDI = destination (début de la mémoire vidéo)
    ; ECX = compteur (nombre de répétitions)
    ; AX = valeur à écrire (espace + attribut blanc)
    ; 
    mov edi, 0xB8000            ; EDI = adresse de l'écran
    mov ecx, 80 * 25            ; ECX = 2000 caractères
    mov ax, 0x0F20              ; AH = 0x0F (blanc sur noir), AL = 0x20 (espace)
    rep stosw                   ; Écrire AX à [EDI] 2000 fois (EDI s'incrémente auto)
    
    ; RÉSULTAT : L'écran est maintenant vide (rempli d'espaces blancs)
    
    ; ========================================
    ; ÉTAPE 4 : AFFICHER LE TITRE
    ; ========================================
    ; 
    ; POSITION :
    ; ----------
    ; Ligne 0, colonne 0 (coin supérieur gauche)
    ; Adresse = 0xB8000 + (ligne * 160) + (colonne * 2)
    ;         = 0xB8000 + 0 + 0
    ;         = 0xB8000
    ; 
    ; TEXTE :
    ; -------
    ; "=== REAPER OS v0.1 - Kernel Mode ==="
    ; Couleur : vert clair (0x0A)
    ; 
    ; MÉTHODE :
    ; ---------
    ; On va copier la chaîne caractère par caractère :
    ; 1. Lire un caractère de la chaîne avec LODSB
    ; 2. Si c'est 0 (fin de chaîne), on a fini
    ; 3. Sinon, écrire le caractère + couleur avec STOSW
    ; 4. Recommencer
    ; 
    mov edi, 0xB8000            ; EDI = destination (écran ligne 0)
    lea esi, [ebx + (msg_title - kernel_start)]  ; ESI = source (adresse du titre)
    mov ah, 0x0A                ; AH = couleur (vert clair sur noir)
.loop_title:
    lodsb                       ; AL = [ESI], ESI++ (lire un caractère)
    cmp al, 0                   ; Est-ce la fin de la chaîne ?
    je .done_title              ; Si oui, on a fini
    stosw                       ; [EDI] = AX, EDI += 2 (écrire caractère + couleur)
    jmp .loop_title             ; Continuer la boucle
.done_title:
    
    ; ========================================
    ; ÉTAPE 5 : AFFICHER LES INFORMATIONS SYSTÈME
    ; ========================================
    ; 
    ; POSITION :
    ; ----------
    ; Ligne 2, colonne 0
    ; Adresse = 0xB8000 + (2 * 160) = 0xB8000 + 320 = 0xB8140
    ; 
    ; TEXTE :
    ; -------
    ; "Systeme d exploitation minimaliste en mode protege 32-bit"
    ; Couleur : blanc (0x0F)
    ; 
    mov edi, 0xB8000 + (160 * 2)  ; EDI = écran ligne 2
    lea esi, [ebx + (msg_info - kernel_start)]  ; ESI = message info
    mov ah, 0x0F                ; AH = blanc sur noir
.loop_info:
    lodsb                       ; Lire un caractère
    cmp al, 0                   ; Fin de chaîne ?
    je .done_info               ; Si oui, terminer
    stosw                       ; Écrire caractère + couleur
    jmp .loop_info              ; Continuer
.done_info:
    
    ; ========================================
    ; ÉTAPE 6 : AFFICHER LES COMMANDES DISPONIBLES
    ; ========================================
    ; 
    ; POSITION :
    ; ----------
    ; Ligne 4, colonne 0
    ; Adresse = 0xB8000 + (4 * 160) = 0xB8000 + 640 = 0xB8280
    ; 
    ; TEXTE :
    ; -------
    ; "Commandes : [H]elp  [C]lear  [R]eboot"
    ; Couleur : bleu clair (0x09)
    ; 
    mov edi, 0xB8000 + (160 * 4)  ; EDI = écran ligne 4
    lea esi, [ebx + (msg_commands - kernel_start)]  ; ESI = message commandes
    mov ah, 0x09                ; AH = bleu clair sur noir
.loop_cmd:
    lodsb                       ; Lire un caractère
    cmp al, 0                   ; Fin de chaîne ?
    je .done_cmd                ; Si oui, terminer
    stosw                       ; Écrire caractère + couleur
    jmp .loop_cmd               ; Continuer
.done_cmd:
    
    ; ========================================
    ; ÉTAPE 7 : AFFICHER LE PROMPT
    ; ========================================
    ; 
    ; POSITION :
    ; ----------
    ; Ligne 6, colonne 0
    ; Adresse = 0xB8000 + (6 * 160) = 0xB8000 + 960 = 0xB83C0
    ; 
    ; TEXTE :
    ; -------
    ; "> Appuyez sur une touche..."
    ; Couleur : blanc (0x0F)
    ; 
    mov edi, 0xB8000 + (160 * 6)  ; EDI = écran ligne 6
    lea esi, [ebx + (msg_prompt - kernel_start)]  ; ESI = message prompt
    mov ah, 0x0F                ; AH = blanc sur noir
.loop_prompt:
    lodsb                       ; Lire un caractère
    cmp al, 0                   ; Fin de chaîne ?
    je .done_prompt             ; Si oui, terminer
    stosw                       ; Écrire caractère + couleur
    jmp .loop_prompt            ; Continuer
.done_prompt:
    
    ; ========================================
    ; BOUCLE PRINCIPALE DU KERNEL
    ; ========================================
    ; 
    ; QU'EST-CE QU'UNE BOUCLE D'ÉVÉNEMENTS ?
    ; ---------------------------------------
    ; La plupart des systèmes d'exploitation fonctionnent avec une
    ; "boucle d'événements" (event loop) :
    ; 
    ; 1. Attendre qu'un événement se produise (touche, souris, réseau...)
    ; 2. Traiter l'événement
    ; 3. Recommencer à l'étape 1
    ; 
    ; C'est exactement ce qu'on fait ici !
    ; 
    ; NOTRE BOUCLE :
    ; --------------
    ; 1. Attendre qu'une touche soit pressée (fonction wait_for_key)
    ; 2. Vérifier quelle touche a été pressée (H, C ou R)
    ; 3. Exécuter la commande correspondante
    ; 4. Recommencer
    ; 
    ; CETTE BOUCLE NE S'ARRÊTE JAMAIS (sauf si on redémarre avec R)
    ; 
kernel_loop:
    ; ========================================
    ; ATTENDRE UNE TOUCHE
    ; ========================================
    ; 
    ; On appelle la fonction wait_for_key (définie plus bas).
    ; Cette fonction :
    ;   - Attend qu'une touche soit pressée
    ;   - Lit le scancode du clavier
    ;   - Le convertit en ASCII
    ;   - Retourne le caractère dans AL
    ; 
    ; APRÈS CET APPEL :
    ; -----------------
    ; AL contient le caractère pressé ('h', 'c' ou 'r')
    ; 
    call wait_for_key           ; Attendre et lire une touche → résultat dans AL
    
    ; ========================================
    ; RECHARGER L'ADRESSE DE BASE
    ; ========================================
    ; 
    ; Pourquoi on recharge EBX ?
    ; --------------------------
    ; EBX contient l'adresse de base du kernel (0x1000).
    ; On en a besoin pour calculer les adresses absolues des messages.
    ; Mais certaines fonctions peuvent modifier EBX, donc on le recharge
    ; depuis la variable [kernel_base] qu'on a sauvegardée au début.
    ; 
    mov ebx, [kernel_base]      ; EBX = 0x1000 (adresse de base du kernel)
    
    ; ========================================
    ; VÉRIFIER QUELLE COMMANDE A ÉTÉ TAPÉE
    ; ========================================
    ; 
    ; On compare AL (la touche pressée) avec chaque commande possible.
    ; Si on trouve une correspondance, on saute au code qui gère cette commande.
    ; 
    ; CMP = CoMPare (comparer)
    ;   Compare deux valeurs et met à jour les flags (ZF, CF, etc.)
    ;   Ne modifie pas les registres, juste les flags
    ; 
    ; JE = Jump if Equal (sauter si égal)
    ;   Saute si le flag ZF = 1 (résultat de la comparaison = égal)
    ; 
    
    ; Est-ce la touche 'h' (help) ?
    cmp al, 'h'                 ; Comparer AL avec 'h' (code ASCII 104)
    je .show_help               ; Si égal, sauter à .show_help
    
    ; Est-ce la touche 'c' (clear) ?
    cmp al, 'c'                 ; Comparer AL avec 'c' (code ASCII 99)
    je .clear                   ; Si égal, sauter à .clear
    
    ; Est-ce la touche 'r' (reboot) ?
    cmp al, 'r'                 ; Comparer AL avec 'r' (code ASCII 114)
    je .reboot                  ; Si égal, sauter à .reboot
    
    ; ========================================
    ; TOUCHE NON RECONNUE
    ; ========================================
    ; 
    ; Si on arrive ici, la touche n'était ni H, ni C, ni R.
    ; On ignore simplement et on retourne au début de la boucle
    ; pour attendre une autre touche.
    ; 
    jmp kernel_loop             ; Recommencer la boucle

; ========================================
; COMMANDE : HELP (AIDE)
; ========================================
; 
; OBJECTIF :
; ----------
; Afficher un message d'aide à la ligne 8 de l'écran.
; Le message explique ce que font les commandes H, C et R.
; 
; APRÈS :
; -------
; On retourne à la boucle principale pour attendre une nouvelle touche.
; 
.show_help:
    ; Calculer la position ligne 8
    ; Adresse = 0xB8000 + (8 * 160) = 0xB8000 + 1280 = 0xB8500
    mov edi, 0xB8000 + (160 * 8)
    
    ; Calculer l'adresse absolue du message d'aide
    ; ESI = adresse de base + offset de msg_help
    lea esi, [ebx + (msg_help - kernel_start)]
    
    ; Couleur : vert clair (0x0A)
    mov ah, 0x0A
    
.loop_help:
    lodsb                       ; Lire un caractère du message
    cmp al, 0                   ; Fin de chaîne ?
    je kernel_loop              ; Si oui, retourner à la boucle principale
    stosw                       ; Écrire caractère + couleur à l'écran
    jmp .loop_help              ; Continuer

; ========================================
; COMMANDE : CLEAR (EFFACER)
; ========================================
; 
; OBJECTIF :
; ----------
; Effacer tout l'écran et réafficher l'interface complète.
; C'est comme un "refresh" de l'écran.
; 
; ÉTAPES :
; --------
; 1. Remplir l'écran d'espaces (effacer)
; 2. Réafficher le titre
; 3. Réafficher les informations
; 4. Réafficher les commandes
; 5. Réafficher le prompt
; 
.clear:
    ; ----------------------------------------
    ; ÉTAPE 1 : EFFACER L'ÉCRAN
    ; ----------------------------------------
    mov edi, 0xB8000            ; EDI = début de l'écran
    mov ecx, 80 * 25            ; ECX = nombre de caractères
    mov ax, 0x0F20              ; AX = espace blanc
    rep stosw                   ; Remplir tout l'écran d'espaces
    
    ; ----------------------------------------
    ; ÉTAPE 2 : RÉAFFICHER LE TITRE (ligne 0)
    ; ----------------------------------------
    mov edi, 0xB8000            ; Ligne 0
    lea esi, [ebx + (msg_title - kernel_start)]  ; Message titre
    mov ah, 0x0A                ; Vert clair
.loop_clear_title:
    lodsb                       ; Lire caractère
    cmp al, 0                   ; Fin ?
    je .clear_info              ; Si oui, passer à l'étape suivante
    stosw                       ; Écrire
    jmp .loop_clear_title       ; Continuer
    
.clear_info:
    ; ----------------------------------------
    ; ÉTAPE 3 : RÉAFFICHER LES INFOS (ligne 2)
    ; ----------------------------------------
    mov edi, 0xB8000 + (160 * 2)  ; Ligne 2
    lea esi, [ebx + (msg_info - kernel_start)]  ; Message info
    mov ah, 0x0F                ; Blanc
.loop_clear_info:
    lodsb                       ; Lire caractère
    cmp al, 0                   ; Fin ?
    je .clear_cmd               ; Si oui, passer à l'étape suivante
    stosw                       ; Écrire
    jmp .loop_clear_info        ; Continuer
    
.clear_cmd:
    ; ----------------------------------------
    ; ÉTAPE 4 : RÉAFFICHER LES COMMANDES (ligne 4)
    ; ----------------------------------------
    mov edi, 0xB8000 + (160 * 4)  ; Ligne 4
    lea esi, [ebx + (msg_commands - kernel_start)]  ; Message commandes
    mov ah, 0x09                ; Bleu clair
.loop_clear_cmd:
    lodsb                       ; Lire caractère
    cmp al, 0                   ; Fin ?
    je .clear_prompt            ; Si oui, passer à l'étape suivante
    stosw                       ; Écrire
    jmp .loop_clear_cmd         ; Continuer
    
.clear_prompt:
    ; ----------------------------------------
    ; ÉTAPE 5 : RÉAFFICHER LE PROMPT (ligne 6)
    ; ----------------------------------------
    mov edi, 0xB8000 + (160 * 6)  ; Ligne 6
    lea esi, [ebx + (msg_prompt - kernel_start)]  ; Message prompt
    mov ah, 0x0F                ; Blanc
.loop_clear_prompt:
    lodsb                       ; Lire caractère
    cmp al, 0                   ; Fin ?
    je kernel_loop              ; Si oui, retourner à la boucle principale
    stosw                       ; Écrire
    jmp .loop_clear_prompt      ; Continuer

; ========================================
; COMMANDE : REBOOT (REDÉMARRER)
; ========================================
; 
; OBJECTIF :
; ----------
; Redémarrer complètement l'ordinateur (reset matériel).
; 
; COMMENT REDÉMARRER UN PC ?
; --------------------------
; Il existe plusieurs méthodes pour redémarrer un PC.
; La méthode la plus simple (mais pas la plus propre) est d'utiliser
; le contrôleur clavier 8042.
; 
; LE CONTRÔLEUR CLAVIER 8042 :
; ----------------------------
; C'est une puce sur la carte mère qui gère le clavier ET le bouton reset.
; Elle a plusieurs ports I/O :
;   - Port 0x60 : données (scancodes du clavier)
;   - Port 0x64 : commandes/statut
; 
; COMMANDE 0xFE :
; ---------------
; Quand on écrit 0xFE sur le port 0x64, le contrôleur 8042 :
;   1. Active la ligne de reset du CPU
;   2. Le CPU redémarre
;   3. Le BIOS reprend le contrôle
;   4. Le système reboote comme si on avait appuyé sur le bouton reset
; 
; ATTENTION :
; -----------
; Cette méthode NE SAUVEGARDE RIEN ! Tout le contenu de la RAM est perdu.
; Dans un vrai OS, on sauvegarderait d'abord les fichiers ouverts, etc.
; 
.reboot:
    ; OUT = OUTput (écrire vers un port I/O)
    ; Syntaxe : OUT port, registre
    ; 
    ; AL = 0xFE (commande "Pulse reset line")
    mov al, 0xFE
    
    ; Envoyer la commande au port 0x64 (contrôleur clavier)
    out 0x64, al
    
    ; ========================================
    ; SI LE REDÉMARRAGE ÉCHOUE
    ; ========================================
    ; 
    ; Normalement, le CPU redémarre immédiatement et on ne revient jamais ici.
    ; Mais sur certaines machines virtuelles ou vieux PCs, la commande 0xFE
    ; peut ne pas fonctionner.
    ; 
    ; Dans ce cas, on fait une boucle infinie pour éviter que le kernel
    ; continue à s'exécuter de façon imprévisible.
    ; 
    ; JMP $ signifie "sauter à l'adresse actuelle"
    ; $ = adresse de cette instruction
    ; Résultat : on saute sur soi-même → boucle infinie
    ; 
    jmp $                       ; Boucle infinie (halt)

; ========================================
; FONCTION : clear_screen
; ========================================
; 
; DESCRIPTION :
; -------------
; Efface tout l'écran en le remplissant d'espaces blancs.
; Cette fonction n'est actuellement pas utilisée car on préfère
; faire l'effacement directement dans le code (plus rapide).
; Mais elle est là au cas où on en aurait besoin ailleurs.
; 
; L'ÉCRAN EN MODE TEXTE VGA :
; ---------------------------
; - Résolution : 80 colonnes x 25 lignes
; - Total : 2000 caractères
; - Mémoire : 4000 octets (2 octets par caractère)
; - Adresse : 0xB8000 à 0xB8FA0
; 
; MÉTHODE :
; ---------
; On remplit toute la mémoire vidéo avec la valeur 0x0F20 :
;   - 0x0F = attribut (blanc sur noir)
;   - 0x20 = caractère (espace)
; 
; PARAMÈTRES :
; ------------
; Aucun
; 
; RETOUR :
; --------
; Aucun (l'écran est effacé)
; 
; REGISTRES MODIFIÉS :
; --------------------
; Aucun (tous sauvegardés/restaurés avec PUSHA/POPA)
; 
clear_screen:
    ; PUSHA : sauvegarder TOUS les registres 32-bit sur la pile
    ; Sauvegarde : EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI (dans cet ordre)
    pusha
    
    ; EDI = adresse de destination
    ; On commence au début de la mémoire vidéo
    mov edi, VIDEO_MEMORY       ; EDI = 0xB8000
    
    ; ECX = compteur pour l'instruction LOOP
    ; 80 colonnes * 25 lignes = 2000 caractères
    mov ecx, 80 * 25            ; ECX = 2000
    
    ; AH = attribut de couleur
    mov ah, WHITE_ON_BLACK      ; AH = 0x0F (blanc sur noir)
    
    ; AL = caractère à afficher
    mov al, ' '                 ; AL = 0x20 (espace)
    
.loop:
    ; Écrire AX (2 octets) à l'adresse [EDI]
    ; AX = AH:AL = 0x0F20 = attribut + caractère
    mov [edi], ax
    
    ; Avancer de 2 octets pour le prochain caractère
    ; EDI += 2
    add edi, 2
    
    ; LOOP : décrémenter ECX et sauter si ECX != 0
    ; Équivalent à : ECX-- ; if (ECX != 0) goto .loop
    loop .loop
    
    ; POPA : restaurer tous les registres depuis la pile
    ; Restaure dans l'ordre inverse de PUSHA
    popa
    
    ; RET : retourner à l'appelant
    ; Dépile l'adresse de retour et saute à cette adresse
    ret

; ========================================
; FONCTION : print_line
; ========================================
; 
; DESCRIPTION :
; -------------
; Affiche une chaîne de caractères à une ligne spécifique de l'écran.
; La chaîne est affichée avec la couleur spécifiée, à partir du début de la ligne.
; 
; CALCUL DE L'ADRESSE :
; ---------------------
; Pour afficher à la ligne N, il faut calculer l'adresse mémoire :
; 
; Adresse = VIDEO_MEMORY + (ligne * octets_par_ligne)
; 
; Octets par ligne = 80 colonnes * 2 octets/caractère = 160 octets
; 
; Exemple :
; - Ligne 0 : 0xB8000 + (0 * 160) = 0xB8000
; - Ligne 1 : 0xB8000 + (1 * 160) = 0xB80A0
; - Ligne 2 : 0xB8000 + (2 * 160) = 0xB8140
; - etc.
; 
; PARAMÈTRES :
; ------------
;   EBX = adresse de la chaîne à afficher (terminée par 0)
;   ECX = attribut de couleur (ex: 0x0F pour blanc sur noir)
;   DL  = numéro de ligne (0-24)
; 
; RETOUR :
; --------
; Aucun (la chaîne est affichée à l'écran)
; 
; REGISTRES MODIFIÉS :
; --------------------
; Aucun (tous sauvegardés/restaurés)
; 
print_line:
    ; Sauvegarder tous les registres
    pusha
    
    ; ========================================
    ; CALCULER L'ADRESSE DE LA LIGNE
    ; ========================================
    
    ; MOVZX EAX, DL : Move with Zero eXtend
    ; Copie DL (8 bits, valeurs 0-255) dans EAX (32 bits)
    ; Les 24 bits supérieurs de EAX sont mis à 0
    ; 
    ; Pourquoi MOVZX et pas MOV ?
    ; ---------------------------
    ; MOV AL, DL copierait seulement le bas de EAX, laissant des déchets dans les bits supérieurs
    ; MOVZX garantit que EAX contient exactement le numéro de ligne, sans bits parasites
    ; 
    movzx eax, dl               ; EAX = numéro de ligne (0-24)
    
    ; EDX = nombre d'octets par ligne
    ; 80 caractères * 2 octets = 160 octets
    mov edx, 160
    
    ; MUL EDX : multiplication non signée
    ; Calcule : EAX = EAX * EDX
    ; EDX:EAX = EAX * EDX (résultat sur 64 bits, mais on n'utilise que EAX)
    ; 
    ; Exemple : ligne 5
    ; EAX = 5, EDX = 160
    ; Résultat : EAX = 5 * 160 = 800 octets
    ; 
    mul edx                     ; EAX = numéro_ligne * 160
    
    ; EDI = adresse de base de la mémoire vidéo
    mov edi, VIDEO_MEMORY       ; EDI = 0xB8000
    
    ; Ajouter l'offset de la ligne
    ; EDI pointe maintenant sur le premier caractère de la ligne voulue
    add edi, eax                ; EDI = 0xB8000 + (ligne * 160)
    
    ; ========================================
    ; PRÉPARER L'ATTRIBUT DE COULEUR
    ; ========================================
    
    ; La couleur est passée dans CL (partie basse de ECX)
    ; On la copie dans AH pour pouvoir l'utiliser avec STOSB/MOVSB
    ; 
    ; Rappel : quand on affiche un caractère, on écrit 2 octets :
    ; - AL = caractère (code ASCII)
    ; - AH = attribut (couleur)
    ; 
    mov ah, cl                  ; AH = attribut de couleur
    
    ; ========================================
    ; BOUCLE D'AFFICHAGE
    ; ========================================
    ; 
    ; On va lire chaque caractère de la chaîne et l'afficher à l'écran
    ; jusqu'à rencontrer le caractère nul (0) qui marque la fin.
    ; 
.loop:
    ; Lire le caractère courant de la chaîne
    ; [EBX] = mémoire à l'adresse EBX
    mov al, [ebx]               ; AL = caractère à afficher
    
    ; Vérifier si c'est la fin de la chaîne
    ; 0 = caractère nul = fin de chaîne (comme en C)
    cmp al, 0                   ; AL == 0 ?
    je .done                    ; Si oui, on a fini → sauter à .done
    
    ; Écrire le caractère + attribut dans la mémoire vidéo
    ; AX = AH:AL = couleur:caractère
    ; [EDI] = emplacement à l'écran
    mov [edi], ax               ; Écrire les 2 octets (caractère + couleur)
    
    ; Avancer au prochain caractère à l'écran
    ; Chaque caractère occupe 2 octets, donc EDI += 2
    add edi, 2                  ; EDI pointe sur le prochain emplacement
    
    ; Avancer au prochain caractère dans la chaîne
    ; Chaque caractère occupe 1 octet, donc EBX += 1
    add ebx, 1                  ; EBX pointe sur le prochain caractère
    
    ; Recommencer la boucle
    jmp .loop
    
.done:
    ; Restaurer tous les registres
    popa
    
    ; Retourner à l'appelant
    ret

; ========================================
; FONCTION : wait_for_key
; ========================================
; 
; DESCRIPTION :
; -------------
; Attend qu'une touche soit pressée sur le clavier et retourne le caractère ASCII.
; Cette fonction gère le clavier PS/2 en mode polling (interrogation active).
; 
; LE CLAVIER PS/2 :
; -----------------
; Le clavier PS/2 est contrôlé par une puce appelée "contrôleur clavier 8042".
; Cette puce communique avec le CPU via deux ports I/O :
; 
;   Port 0x60 : PORT DE DONNÉES
;     - En lecture : lit le scancode de la dernière touche pressée
;     - En écriture : envoie des commandes au clavier
;   
;   Port 0x64 : PORT DE STATUT/COMMANDE
;     - En lecture : lit le registre de statut (8 bits de flags)
;     - En écriture : envoie des commandes au contrôleur
; 
; REGISTRE DE STATUT (port 0x64) :
; ---------------------------------
;   Bit 0 : Output Buffer Full (OBF)
;           1 = des données sont disponibles dans le port 0x60
;           0 = aucune donnée disponible
;   
;   Bit 1 : Input Buffer Full (IBF)
;           1 = le contrôleur est occupé (ne pas écrire)
;           0 = le contrôleur est prêt
;   
;   Bits 2-7 : autres flags (erreurs, timeouts, etc.)
; 
; SCANCODES :
; -----------
; Quand on appuie sur une touche, le clavier envoie un "scancode" (code de touche).
; Les scancodes sont des nombres qui identifient chaque touche physique du clavier.
; Ils ne correspondent PAS directement aux codes ASCII !
; 
; Exemples de scancodes (clavier QWERTY US) :
;   0x1E = touche A
;   0x23 = touche H
;   0x2E = touche C
;   0x13 = touche R
;   0x1C = touche Entrée
;   0x01 = touche Échap
; 
; MAKE CODE vs BREAK CODE :
; -------------------------
; - Make code : envoyé quand on APPUIE sur une touche
; - Break code : envoyé quand on RELÂCHE une touche (= make code + 0x80)
; 
; Exemple :
; - Appuyer sur H : scancode 0x23
; - Relâcher H : scancode 0xA3 (0x23 + 0x80)
; 
; Dans notre fonction, on ignore les break codes (bit 7 = 1).
; 
; CONVERSION SCANCODE → ASCII :
; -----------------------------
; Pour convertir un scancode en ASCII, un vrai OS utilise une "keymap" (table de conversion).
; Cette table prend en compte :
;   - La disposition du clavier (QWERTY, AZERTY, QWERTZ...)
;   - Les touches modificatrices (Shift, Ctrl, Alt, AltGr...)
;   - Le verrouillage des majuscules (Caps Lock)
;   - Le pavé numérique (Num Lock)
; 
; Notre version simplifiée gère seulement 3 touches (H, C, R) sans modificateurs.
; 
; PARAMÈTRES :
; ------------
; Aucun
; 
; RETOUR :
; --------
; AL = caractère ASCII de la touche pressée ('h', 'c' ou 'r')
;      Si la touche n'est pas reconnue, AL est indéfini
; 
; REGISTRES MODIFIÉS :
; --------------------
; AL (contient le caractère)
; EBX est sauvegardé/restauré
; 
wait_for_key:
    ; Sauvegarder EBX (on l'utilise temporairement dans la fonction)
    push ebx
    
.wait:
    ; ========================================
    ; ÉTAPE 1 : ATTENDRE QU'UNE DONNÉE SOIT DISPONIBLE
    ; ========================================
    ; 
    ; On lit le port de statut (0x64) en boucle jusqu'à ce que
    ; le bit 0 (OBF = Output Buffer Full) soit à 1.
    ; 
    ; IN AL, port : lire 1 octet depuis un port I/O
    ; Syntaxe : IN destination, port
    ; 
    ; Après cette instruction :
    ; AL contient le registre de statut (8 bits de flags)
    ; 
    in al, 0x64                 ; AL = registre de statut du contrôleur clavier
    
    ; TEST AL, 1 : tester le bit 0 de AL
    ; TEST fait un AND logique SANS modifier AL
    ; Résultat : met à jour le Zero Flag (ZF)
    ; 
    ; ZF = 1 si (AL & 1) == 0 (bit 0 = 0, pas de données)
    ; ZF = 0 si (AL & 1) != 0 (bit 0 = 1, données disponibles)
    ; 
    test al, 1                  ; Tester le bit 0 (OBF)
    
    ; JZ = Jump if Zero (sauter si ZF = 1)
    ; Si le bit 0 était à 0, aucune donnée n'est prête
    ; → recommencer la boucle d'attente
    jz .wait                    ; Si pas de données, continuer d'attendre
    
    ; Si on arrive ici, le bit 0 était à 1
    ; → des données sont disponibles dans le port 0x60
    
    ; ========================================
    ; ÉTAPE 2 : LIRE LE SCANCODE
    ; ========================================
    ; 
    ; Maintenant qu'on sait que des données sont prêtes,
    ; on les lit depuis le port 0x60.
    ; 
    in al, 0x60                 ; AL = scancode de la touche pressée
    
    ; ========================================
    ; ÉTAPE 3 : IGNORER LES BREAK CODES
    ; ========================================
    ; 
    ; Les break codes (relâchement de touche) ont le bit 7 = 1.
    ; On veut seulement les make codes (appui de touche).
    ; 
    ; Test du bit 7 :
    ; TEST AL, 0x80 teste si le bit 7 de AL est à 1
    ; 0x80 = 10000000 en binaire
    ; 
    test al, 0x80               ; Tester le bit 7
    jnz .wait                   ; Si bit 7 = 1 (break code), ignorer et recommencer
    
    ; ========================================
    ; ÉTAPE 4 : CONVERTIR LE SCANCODE EN ASCII
    ; ========================================
    ; 
    ; TABLE DE CONVERSION (pour clavier QWERTY US) :
    ; -----------------------------------------------
    ; Scancode → ASCII
    ; 0x23 → 'h' (104 en décimal, 0x68 en hexa)
    ; 0x2E → 'c' (99 en décimal, 0x63 en hexa)
    ; 0x13 → 'r' (114 en décimal, 0x72 en hexa)
    ; 
    ; On compare AL avec chaque scancode connu.
    ; Si on trouve une correspondance, on convertit en ASCII et on retourne.
    ; 
    
    ; Est-ce la touche H ?
    cmp al, 0x23                ; Comparer avec le scancode de H
    je .key_h                   ; Si égal, sauter à .key_h
    
    ; Est-ce la touche C ?
    cmp al, 0x2E                ; Comparer avec le scancode de C
    je .key_c                   ; Si égal, sauter à .key_c
    
    ; Est-ce la touche R ?
    cmp al, 0x13                ; Comparer avec le scancode de R
    je .key_r                   ; Si égal, sauter à .key_r
    
    ; ========================================
    ; TOUCHE NON RECONNUE
    ; ========================================
    ; 
    ; Si on arrive ici, le scancode ne correspond à aucune de nos touches.
    ; On restaure EBX et on retourne sans modifier AL.
    ; L'appelant devra vérifier si la touche est valide.
    ; 
    ; Dans notre kernel, on ignore simplement les touches inconnues
    ; et on recommence la boucle principale.
    ; 
    pop ebx                     ; Restaurer EBX
    ret                         ; Retourner (AL contient le scancode brut)

.key_h:
    ; Conversion : scancode 0x23 → ASCII 'h' (0x68)
    mov al, 'h'                 ; AL = 104 = 'h'
    pop ebx                     ; Restaurer EBX
    ret                         ; Retourner avec AL = 'h'

.key_c:
    ; Conversion : scancode 0x2E → ASCII 'c' (0x63)
    mov al, 'c'                 ; AL = 99 = 'c'
    pop ebx                     ; Restaurer EBX
    ret                         ; Retourner avec AL = 'c'

.key_r:
    ; Conversion : scancode 0x13 → ASCII 'r' (0x72)
    mov al, 'r'                 ; AL = 114 = 'r'
    pop ebx                     ; Restaurer EBX
    ret                         ; Retourner avec AL = 'r'

; ========================================
; SECTION DE DONNÉES DU KERNEL
; ========================================
; 
; QU'EST-CE QUE LA SECTION DE DONNÉES ?
; --------------------------------------
; En programmation, on sépare généralement :
;   - Le CODE (les instructions : mov, add, jmp, etc.)
;   - Les DONNÉES (les variables, constantes, chaînes, etc.)
; 
; Cette section contient toutes les données statiques du kernel :
;   - Variables globales
;   - Chaînes de caractères (messages affichés à l'écran)
;   - Tables et structures de données
; 
; EN ASSEMBLEUR :
; ---------------
; Pour définir des données, on utilise des directives :
;   - DB (Define Byte) : définit 1 ou plusieurs octets
;   - DW (Define Word) : définit 1 ou plusieurs mots (2 octets)
;   - DD (Define Double word) : définit 1 ou plusieurs double-mots (4 octets)
;   - DQ (Define Quad word) : définit 1 ou plusieurs quad-mots (8 octets)
; 
; CHAÎNES DE CARACTÈRES :
; -----------------------
; En assembleur, une chaîne est simplement une suite d'octets en mémoire.
; Par convention (héritée du langage C), on termine les chaînes par un octet nul (0).
; Ce 0 s'appelle le "null terminator" ou "sentinelle".
; 
; Exemple :
;   msg: db 'Hello', 0
; 
; En mémoire, ça donne : [48 65 6C 6C 6F 00]
;                         H  e  l  l  o  \0
; 
; Pour afficher une chaîne, on lit les octets un par un jusqu'à trouver 0.
; 
; ========================================

; ========================================
; VARIABLE : kernel_base
; ========================================
; 
; DESCRIPTION :
; -------------
; Cette variable stocke l'adresse de base du kernel en mémoire.
; Elle est calculée au démarrage avec la technique PIC (position-independent code).
; 
; POURQUOI ON EN A BESOIN ?
; --------------------------
; Le kernel est compilé sans [ORG], donc les labels (msg_title, msg_info, etc.)
; sont des OFFSETS depuis le début du fichier, pas des adresses ABSOLUES.
; 
; Pour obtenir l'adresse absolue d'un label :
;   adresse_absolue = kernel_base + (label - kernel_start)
; 
; EXEMPLE :
; ---------
; Si msg_title est à l'offset 0x16B dans le fichier kernel.bin,
; et que kernel_base = 0x1000 (où le kernel est chargé),
; alors l'adresse absolue de msg_title est :
;   0x1000 + 0x16B = 0x116B
; 
; TYPE :
; ------
; DD = Define Double word (4 octets = 32 bits)
; C'est la taille parfaite pour stocker une adresse en mode 32-bit.
; 
; INITIALISATION :
; ----------------
; On l'initialise à 0, elle sera remplie au démarrage du kernel.
; 
kernel_base:    dd 0            ; Adresse de base du kernel (calculée au démarrage)

; ========================================
; MESSAGE : msg_title
; ========================================
; 
; DESCRIPTION :
; -------------
; Titre principal affiché en haut de l'écran (ligne 0).
; C'est la première chose que l'utilisateur voit au démarrage.
; 
; CONTENU :
; ---------
; "=== REAPER OS v0.1 - Kernel Mode ==="
; 
; LONGUEUR :
; ----------
; 37 caractères + 1 octet nul = 38 octets
; 
; COULEUR :
; ---------
; Affiché en vert clair (0x0A) sur fond noir.
; Le vert est traditionnellement utilisé pour les messages système.
; 
; STYLE :
; -------
; Les === donnent un aspect "encadré" professionnel.
; Le numéro de version permet de suivre les évolutions.
; "Kernel Mode" indique qu'on est en mode protégé (vs "Real Mode").
; 
msg_title:      db '=== REAPER OS v0.1 - Kernel Mode ===', 0

; ========================================
; MESSAGE : msg_info
; ========================================
; 
; DESCRIPTION :
; -------------
; Description technique du système, affichée à la ligne 2.
; Informe l'utilisateur du type de système qui tourne.
; 
; CONTENU :
; ---------
; "Systeme d exploitation minimaliste en mode protege 32-bit"
; 
; LONGUEUR :
; ----------
; 59 caractères + 1 octet nul = 60 octets
; 
; COULEUR :
; ---------
; Affiché en blanc (0x0F) sur fond noir.
; Blanc = neutre, pour de l'information générale.
; 
; INFORMATIONS TECHNIQUES :
; -------------------------
; - "Système d'exploitation" : c'est bien un OS (même basique)
; - "Minimaliste" : pas de fonctionnalités avancées (multitâche, réseau, etc.)
; - "Mode protégé" : le CPU est en mode 32-bit avec protection mémoire
; - "32-bit" : les registres et adresses sont sur 32 bits (vs 16 ou 64 bits)
; 
msg_info:       db 'Systeme d exploitation minimaliste en mode protege 32-bit', 0

; ========================================
; MESSAGE : msg_commands
; ========================================
; 
; DESCRIPTION :
; -------------
; Liste des commandes disponibles, affichée à la ligne 4.
; Guide l'utilisateur sur ce qu'il peut faire.
; 
; CONTENU :
; ---------
; "Commandes : [H]elp  [C]lear  [R]eboot"
; 
; LONGUEUR :
; ----------
; 38 caractères + 1 octet nul = 39 octets
; 
; COULEUR :
; ---------
; Affiché en bleu clair (0x09) sur fond noir.
; Bleu = informatif, pour attirer l'attention sur les commandes.
; 
; FORMAT :
; --------
; Les [] autour de H, C et R indiquent les touches à presser.
; C'est une convention courante dans les interfaces texte.
; 
; COMMANDES :
; -----------
; H = Help (aide) : affiche un message d'aide détaillé
; C = Clear (effacer) : efface l'écran et réaffiche l'interface
; R = Reboot (redémarrer) : redémarre complètement l'ordinateur
; 
msg_commands:   db 'Commandes : [H]elp  [C]lear  [R]eboot', 0

; ========================================
; MESSAGE : msg_prompt
; ========================================
; 
; DESCRIPTION :
; -------------
; Prompt (invite) affiché à la ligne 6.
; Indique à l'utilisateur qu'on attend une action de sa part.
; 
; CONTENU :
; ---------
; "> Appuyez sur une touche..."
; 
; LONGUEUR :
; ----------
; 29 caractères + 1 octet nul = 30 octets
; 
; COULEUR :
; ---------
; Affiché en blanc (0x0F) sur fond noir.
; 
; SYMBOLE > :
; -----------
; Le symbole ">" est universellement reconnu comme un prompt.
; On le retrouve dans :
;   - Les shells Unix/Linux (bash, zsh...)
;   - L'invite de commande DOS/Windows
;   - Les interfaces REPL (Read-Eval-Print Loop)
; 
msg_prompt:     db '> Appuyez sur une touche...', 0

; ========================================
; MESSAGE : msg_help
; ========================================
; 
; DESCRIPTION :
; -------------
; Message d'aide détaillé, affiché quand l'utilisateur appuie sur H.
; Explique brièvement ce que fait chaque commande.
; 
; CONTENU :
; ---------
; "H = Aide  |  C = Effacer ecran  |  R = Redemarrer"
; 
; LONGUEUR :
; ----------
; 51 caractères + 1 octet nul = 52 octets
; 
; COULEUR :
; ---------
; Affiché en vert clair (0x0A) sur fond noir.
; 
; FORMAT :
; --------
; Chaque commande est expliquée avec le format : TOUCHE = ACTION
; Les | (pipes) séparent visuellement les différentes commandes.
; 
; POURQUOI CE MESSAGE ?
; ---------------------
; Dans un vrai OS, la commande Help afficherait une page complète
; avec toutes les fonctionnalités, la syntaxe, des exemples, etc.
; Ici, on se contente d'un rappel concis car on n'a que 3 commandes.
; 
msg_help:       db 'H = Aide  |  C = Effacer ecran  |  R = Redemarrer', 0

; ========================================
; REMPLISSAGE DU KERNEL (PADDING)
; ========================================
; 
; POURQUOI REMPLIR ?
; ------------------
; On veut que le kernel ait une taille FIXE de 10 KB (10240 octets).
; 
; RAISONS :
; ---------
; 1. SIMPLICITÉ DU BOOTLOADER
;    Le bootloader charge un nombre fixe de secteurs (20 secteurs = 10 KB).
;    Si le kernel avait une taille variable, il faudrait :
;      - Soit coder la taille dans un header
;      - Soit utiliser un système de fichiers
;    Avec une taille fixe, c'est beaucoup plus simple !
; 
; 2. ALIGNEMENT MÉMOIRE
;    10 KB = 10240 octets = 20 secteurs de 512 octets.
;    Les secteurs sont l'unité de base pour les opérations disque.
;    En ayant une taille multiple de 512, on évite les problèmes d'alignement.
; 
; 3. ESPACE POUR GRANDIR
;    Actuellement, le kernel fait environ 500-600 octets.
;    On a donc 9+ KB d'espace libre pour ajouter du code plus tard !
; 
; COMMENT ÇA MARCHE ?
; -------------------
; TIMES n DB value : répète "DB value" n fois
; 
; $ = adresse actuelle (où on est dans le code)
; $$ = adresse de début de section (kernel_start = 0)
; $ - $$ = nombre d'octets déjà écrits
; 
; 10240 - ($-$$) = nombre d'octets restants pour atteindre 10240
; 
; Exemple :
; Si on a déjà écrit 600 octets, il reste : 10240 - 600 = 9640 octets à remplir
; 
; AVEC QUOI ON REMPLIT ?
; ----------------------
; On remplit avec des 0.
; Les zéros sont les plus sûrs car :
;   - En code x86, 0x00 0x00 = ADD [EAX], AL (instruction inoffensive)
;   - Si le CPU exécute accidentellement cette zone, ça ne plantera pas violemment
;   - Les outils de debug montrent clairement les zones non utilisées
; 
; Alternative : on pourrait remplir avec 0xCC (INT 3 = breakpoint)
; pour détecter si le CPU exécute du code invalide.
; 
times 10240-($-$$) db 0     ; Remplir jusqu'à 10 KB avec des zéros

; ========================================
; MARQUEUR DE FIN DU KERNEL
; ========================================
; 
; DESCRIPTION :
; -------------
; Simple label qui marque la fin du kernel.
; Pas de code ici, c'est juste une étiquette symbolique.
; 
; UTILITÉ :
; ---------
; 1. DÉBOGAGE
;    Dans un débogueur, on peut voir où se termine le kernel.
; 
; 2. CALCULS DE TAILLE
;    On pourrait calculer : taille_kernel = kernel_end - kernel_start
;    (mais ici, on sait déjà que c'est 10240 octets)
; 
; 3. DOCUMENTATION
;    Ça rend le code plus clair et plus lisible.
; 
kernel_end:

; ========================================
; FIN DU FICHIER KERNEL.ASM
; ========================================
; 
; RÉCAPITULATIF DE CE QUI A ÉTÉ CRÉÉ :
; -------------------------------------
; 
; 1. UN VRAI KERNEL EN MODE PROTÉGÉ 32-BIT
;    - Pas de dépendance au BIOS
;    - Accès direct au matériel (VGA, clavier)
;    - Architecture modulaire avec des fonctions
; 
; 2. INTERFACE UTILISATEUR
;    - Affichage en couleur
;    - Messages informatifs
;    - Feedback visuel clair
; 
; 3. GESTION DU CLAVIER
;    - Polling du contrôleur 8042
;    - Conversion scancodes → ASCII
;    - Reconnaissance de commandes
; 
; 4. COMMANDES INTERACTIVES
;    - Help : afficher l'aide
;    - Clear : rafraîchir l'écran
;    - Reboot : redémarrer le PC
; 
; 5. CODE BIEN STRUCTURÉ
;    - Séparation code/données
;    - Fonctions réutilisables
;    - Commentaires détaillés
; 
; ARCHITECTURE COMPLÈTE DU SYSTÈME :
; -----------------------------------
; 
; 1. BIOS (firmware de la carte mère)
;    ↓ Charge le secteur de boot à 0x7C00
; 
; 2. STAGE 1 BOOTLOADER (boot_stage1.asm)
;    - 512 octets (1 secteur)
;    - En mode réel 16-bit
;    - Charge le stage 2 depuis le disque
;    ↓
; 
; 3. STAGE 2 BOOTLOADER (boot_stage2.asm)
;    - 2048 octets (4 secteurs)
;    - Charge le kernel depuis le disque
;    - Configure la GDT (Global Descriptor Table)
;    - Passe en mode protégé 32-bit
;    ↓
; 
; 4. KERNEL (kernel.asm - CE FICHIER)
;    - 10240 octets (20 secteurs)
;    - Tourne en mode protégé 32-bit
;    - Gère l'affichage et le clavier
;    - Boucle d'événements interactive
; 
; TAILLE TOTALE DU SYSTÈME :
; ---------------------------
; Stage 1 :     512 octets
; Stage 2 :    2048 octets
; Kernel :    10240 octets
; ─────────────────────────
; TOTAL :     12800 octets = 12.5 KB
; 
; Pour comparaison :
; - Un emoji en UTF-8 : 4 octets
; - Une photo moyenne : 2-5 MB
; - Windows 11 : 20+ GB
; 
; Notre OS tient dans 12.5 KB ! 🎉
; 
; AMÉLIORATIONS POSSIBLES :
; -------------------------
; 
; 1. GESTIONNAIRE D'INTERRUPTIONS (IDT)
;    - Gérer les exceptions CPU (division par zéro, page fault...)
;    - Gérer les interruptions matérielles (timer, clavier...)
;    - Permet d'avoir un clavier basé sur interruptions (plus efficace)
; 
; 2. GESTION COMPLÈTE DU CLAVIER
;    - Table de conversion scancode → ASCII complète
;    - Support des modificateurs (Shift, Ctrl, Alt)
;    - Support des touches spéciales (F1-F12, flèches...)
;    - Support de différentes dispositions (AZERTY, QWERTZ...)
; 
; 3. AFFICHAGE AVANCÉ
;    - Scrolling (défilement) automatique
;    - Gestion du curseur clignotant
;    - Support de plusieurs pages vidéo
;    - Mode graphique VGA (320x200, 640x480...)
; 
; 4. SHELL INTERACTIF
;    - Buffer d'édition de commandes
;    - Historique des commandes (flèche haut/bas)
;    - Auto-complétion
;    - Support de paramètres
; 
; 5. SYSTÈME DE FICHIERS
;    - Lecture/écriture de fichiers sur disque
;    - Système FAT12/16 ou ext2 simplifié
;    - Chargement de programmes depuis le disque
; 
; 6. GESTIONNAIRE DE MÉMOIRE
;    - Allocateur dynamique (malloc/free)
;    - Pagination (gestion mémoire virtuelle)
;    - Protection mémoire entre processus
; 
; 7. MULTITÂCHE
;    - Ordonnanceur de processus (scheduler)
;    - Changement de contexte (context switching)
;    - Plusieurs programmes en même temps
; 
; 8. DRIVERS DE PÉRIPHÉRIQUES
;    - Disque dur (IDE/SATA)
;    - Souris PS/2 ou USB
;    - Horloge temps réel (RTC)
;    - Timer programmable (PIT)
;    - Port série (COM1, COM2)
; 
; 9. RÉSEAU
;    - Driver carte réseau (NIC)
;    - Pile TCP/IP simplifiée
;    - Serveur web minimaliste
; 
; 10. MODE 64-BIT (LONG MODE)
;     - Support du mode x86-64
;     - Accès à plus de 4 GB de RAM
;     - Registres 64-bit (RAX, RBX...)
; 
; RESSOURCES POUR ALLER PLUS LOIN :
; ----------------------------------
; 
; Sites web :
; - OSDev Wiki : https://wiki.osdev.org/
; - OSDev Forums : https://forum.osdev.org/
; - Intel® 64 and IA-32 Architectures Software Developer Manuals
; 
; Livres :
; - "Operating Systems: Design and Implementation" (Tanenbaum)
; - "Modern Operating Systems" (Tanenbaum)
; - "Operating System Concepts" (Silberschatz, Galvin, Gagne)
; 
; Projets open-source à étudier :
; - Linux Kernel (très complexe, mais instructif)
; - MINIX (plus simple, pédagogique)
; - SerenityOS (moderne, bien documenté)
; - ToaruOS (complet, commenté)
; 
; ========================================
; BRAVO !
; ========================================
; 
; Si vous êtes arrivé jusqu'ici et que vous comprenez ce code,
; vous avez maintenant une bonne base pour créer votre propre OS !
; 
; Vous comprenez :
; ✓ Le processus de boot complet (BIOS → bootloader → kernel)
; ✓ La différence entre mode réel et mode protégé
; ✓ Comment le CPU accède à la mémoire (segmentation, adressage)
; ✓ Comment afficher du texte sans le BIOS (mémoire vidéo VGA)
; ✓ Comment lire le clavier sans le BIOS (ports I/O, scancodes)
; ✓ L'architecture d'un kernel basique (boucle d'événements)
; ✓ La séparation code/données
; ✓ Les bases de l'assembleur x86 (instructions, registres, flags)
; 
; C'est un excellent point de départ pour explorer le développement
; de systèmes d'exploitation !
; 
; N'hésitez pas à expérimenter, casser, réparer, et apprendre ! 🚀
; 
; ========================================
;   - Drivers de périphériques
;   - Shell avec commandes avancées
; ========================================
