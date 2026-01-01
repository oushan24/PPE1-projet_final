#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Ce programme demande deux arguments : 1 fichier d'entrée contenant des urls et 1 fichier sortie"
    exit
fi

FICHIER_URLS=$1
SORTIE=$2

if [ ! -f "$FICHIER_URLS" ]; then
    echo "Ce programme demande un fichier"
    exit
fi

NB_LIGNE=0

cat > "$SORTIE" <<EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.4/css/bulma.min.css"/>
    <link rel="stylesheet" href="../fiche_css/tableau.css"/>
</head>
<body>
<div class="table-container">
    <h2>Analyse des URLs russes</h2>
    <table class="table is-striped is-hoverable is-fullwidth">
        <thead>
            <tr>
                <th><abbr title="Numéro">N°</abbr></th>
                <th>Adresse (URL)</th>
                <th>Réponse requête</th>
                <th>Encodage</th>
                <th>Nombre de mots</th>
                <th>Nombre d'occurrences du mot cible</th>
                <th>Aspiration des pages</th>
                <th>Dump textuel</th>
                <th>Contexte</th>
                <th>Concordancier</th>
                <th>Spécificité</th>
            </tr>
        </thead>
        <tbody>
EOF

# Créer les dossiers nécessaires
mkdir -p "../aspirations"
mkdir -p "../dump"
mkdir -p "../contextes"
mkdir -p "../concordanciers"
mkdir -p "../specificite"

MOT_CIBLE_REGEX="нагрузк(а|и|у|ой|е|ам|ами|ах)|нагрузок"

while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    if [[ $LINE =~ ^https?:// ]]; then

        NB_LIGNE=$((NB_LIGNE + 1))

        # Détection du code HTTP et de l'encodage
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "$LINE")
        
        if [ "$CODE" = "000" ] || [ "$CODE" = "0" ]; then
            echo "<tr><td>$NB_LIGNE</td><td>$LINE</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td></tr>" >> "$SORTIE"
            continue
        fi

        # Récupérer le contenu pour détecter l'encodage et compter les mots
        CONTENT=$(curl -s -L "$LINE")
        
        # Détection de l'encodage
        ENCODAGE=$(echo "$CONTENT" | grep -i "charset=" | head -n1 | grep -E -o "charset=.*" | cut -d= -f2 | tr -d ' >"/')
        
        if [ -z "$ENCODAGE" ]; then
            ENCODAGE_OU_PAS="-"
        else
            # Normaliser l'encodage détecté
            if [[ "$ENCODAGE" =~ (UTF-8|utf-8|UTF8) ]]; then
                ENCODAGE_OU_PAS="UTF-8"
            elif [[ "$ENCODAGE" =~ (windows-1251|cp1251|Windows-1251) ]]; then
                ENCODAGE_OU_PAS="Windows-1251"
            else
                ENCODAGE_OU_PAS="$ENCODAGE"
            fi
        fi

        # Compter le nombre de mots
        NB_MOTS=$(echo "$CONTENT" | lynx -stdin -dump 2>/dev/null | wc -w)

        # Aspiration des pages
        FICHIER_ASP="../aspirations/russe-${NB_LIGNE}.html"
        echo "Téléchargement ($NB_LIGNE): $LINE"
        curl -s -L -o "$FICHIER_ASP" "$LINE"
        
        # Vérifier si le téléchargement a réussi
        if [ ! -s "$FICHIER_ASP" ]; then
            echo "<tr><td>$NB_LIGNE</td><td>$LINE</td><td>$CODE</td><td>$ENCODAGE_OU_PAS</td><td>$NB_MOTS</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td></tr>" >> "$SORTIE"
            continue
        fi
        
        ASPIRATION="<a href='$FICHIER_ASP' target='_blank'>Aspiration n°$NB_LIGNE</a>"

        # Extraction du texte avec gestion d'encodage russe
        FICHIER_DUMP="../dump/russe-${NB_LIGNE}.txt"
        
        # Utiliser l'encodage détecté pour la conversion
        if [ "$ENCODAGE_OU_PAS" = "UTF-8" ] || [ "$ENCODAGE_OU_PAS" = "-" ]; then
            # Essayer UTF-8 d'abord
            lynx -dump -nolist -display_charset=utf-8 "$FICHIER_ASP" 2>/dev/null > "$FICHIER_DUMP"
        elif [ "$ENCODAGE_OU_PAS" = "Windows-1251" ]; then
            # Convertir de Windows-1251 à UTF-8
            iconv -f windows-1251 -t UTF-8 "$FICHIER_ASP" 2>/dev/null | lynx -dump -nolist -stdin 2>/dev/null > "$FICHIER_DUMP"
        else
            # Essayer par défaut avec UTF-8
            lynx -dump -nolist -display_charset=utf-8 "$FICHIER_ASP" 2>/dev/null > "$FICHIER_DUMP"
        fi
        
        # Si le fichier est vide, essayer une méthode de secours
        if [ ! -s "$FICHIER_DUMP" ]; then
            # Méthode alternative: extraire le texte directement du contenu téléchargé
            echo "$CONTENT" | lynx -stdin -dump 2>/dev/null > "$FICHIER_DUMP"
        fi
        
        DUMP="<a href='$FICHIER_DUMP' target='_blank'>Texte n°$NB_LIGNE</a>"

        # Compter le nombre d'occurrences du mot cible dans le dump
        if [ -s "$FICHIER_DUMP" ]; then
            # Recherche insensible à la casse avec formes correctes
            NB_OCCURENCES=$(grep -o -i -E "$MOT_CIBLE_REGEX" "$FICHIER_DUMP" | wc -l | awk '{print $1}')
        else
            NB_OCCURENCES=0
        fi

        # Contexte (quelques lignes autour du mot cible)
        FICHIER_CONTX="../contextes/russe-${NB_LIGNE}.txt"
        if [ -s "$FICHIER_DUMP" ] && [ "$NB_OCCURENCES" -gt 0 ]; then
            grep -i -E -C 3 "$MOT_CIBLE_REGEX" "$FICHIER_DUMP" > "$FICHIER_CONTX" 2>/dev/null || echo "Aucun contexte trouvé" > "$FICHIER_CONTX"
        else
            echo "Aucune occurrence du mot cible" > "$FICHIER_CONTX"
        fi
        CONTEXTE="<a href='$FICHIER_CONTX' target='_blank'>Contexte n°$NB_LIGNE</a>"

        # Spécificité (textométrie)
        FICHIER_TEMP_TOK="temp_tokens_russe.txt"
        FICHIER_SPE="../specificite/specificite_russe-${NB_LIGNE}.tsv"
        
        if [ -s "$FICHIER_DUMP" ]; then
            # Extraction des mots russes (lettres cyrilliques)
            grep -oE "[а-яА-ЯёЁ]+" "$FICHIER_DUMP" > "$FICHIER_TEMP_TOK"

            # Vérifier si le fichier de tokens n'est pas vide
            if [ -s "$FICHIER_TEMP_TOK" ]; then
                python3 ../specificite/cooccurrents.py --target "$MOT_CIBLE_REGEX" "$FICHIER_TEMP_TOK" -N 10 -s i --match-mode regex > "$FICHIER_SPE" 2>/dev/null || echo "Aucune spécificité trouvée" > "$FICHIER_SPE"
            else
                echo "Aucun token russe trouvé" > "$FICHIER_SPE"
            fi
            
            rm -f "$FICHIER_TEMP_TOK" 2>/dev/null
        else
            echo "Fichier dump vide" > "$FICHIER_SPE"
        fi

        SPECIFICITE="<a href='$FICHIER_SPE' target='_blank'>Spécificité n°$NB_LIGNE</a>"

        # Concordancier
        FICHIER_CONCO="../concordanciers/russe-${NB_LIGNE}.html"
        cat > "$FICHIER_CONCO" <<EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.4/css/bulma.min.css"/>
    <link rel="stylesheet" href="../fiche_css/tableau.css"/>
</head>
<body>
    <div class="table-container">
        <h2>Concordancier russe</h2>
        <table class="table is-striped is-hoverable is-fullwidth">
            <thead>
                <tr>
                    <th class="has-text-left">Contexte Gauche</th>
                    <th>Mot cible</th>
                    <th class="has-text-right">Contexte Droit</th>
                </tr>
            </thead>
            <tbody>
EOF
        
        # Extraction du contexte gauche/droit pour le concordancier
        if [ -s "$FICHIER_CONTX" ] && [ "$NB_OCCURENCES" -gt 0 ]; then
            # Utiliser awk pour un traitement plus précis
            awk -v regex="$MOT_CIBLE_REGEX" '
            BEGIN {
                IGNORECASE = 1
            }
            /нагрузк(а|и|у|ой|е|ам|ами|ах)|нагрузок/ {
                line = $0
                # Convertir en minuscules pour la recherche
                line_lower = tolower(line)
                
                # Trouver la position et la longueur du match
                match(line_lower, regex)
                if (RSTART > 0) {
                    # Extraire les parties
                    gauche = substr(line, 1, RSTART - 1)
                    cible = substr(line, RSTART, RLENGTH)
                    droite = substr(line, RSTART + RLENGTH)
                    
                    # Nettoyer les espaces en début/fin
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", gauche)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cible)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", droite)
                    
                    print "<tr><td>" gauche "</td><td>" cible "</td><td>" droite "</td></tr>"
                }
            }' "$FICHIER_CONTX" >> "$FICHIER_CONCO" 2>/dev/null
        else
            echo "<tr><td colspan='3'>Aucun contexte disponible</td></tr>" >> "$FICHIER_CONCO"
        fi

        cat >> "$FICHIER_CONCO" <<EOF
            </tbody>
        </table>
    </div>
</body>
</html>
EOF
        
        CONCORDANCIER="<a href='$FICHIER_CONCO' target='_blank'>Concordancier n°$NB_LIGNE</a>"

        # Tableau final avec toutes les infos
        echo "<tr><td>$NB_LIGNE</td><td id='url'>$LINE</td><td>$CODE</td><td>$ENCODAGE_OU_PAS</td><td>$NB_MOTS</td><td>$NB_OCCURENCES</td><td>$ASPIRATION</td><td>$DUMP</td><td>$CONTEXTE</td><td>$CONCORDANCIER</td><td>$SPECIFICITE</td></tr>" >> "$SORTIE"

        # Pause pour éviter de surcharger le serveur
        sleep 1
    fi
done < "$FICHIER_URLS"

cat >> "$SORTIE" <<EOF
        </tbody>
     </table>
    </div>
</body>
</html>
EOF

# Nettoyage des fichiers temporaires
rm -f tmp_russe.txt 2>/dev/null
rm -f temp_tokens_russe.txt 2>/dev/null

echo "Analyse terminée. Résultats dans: $SORTIE"