#!/usr/bin/bash
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

NB_LIGNE=0 # on aurait pu mettre lineno

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
    <h2>Analyse des URLs</h2>
    <table class="table is-striped is-hoverable is-fullwidth">
        <thead>
            <tr>
                <th><abbr title="Numéro">N°</abbr></th>
                <th>Adresse (URL)</th>
                <th>Réponse requête</th>
                <th>Encodage</th>
                <th>Nombre de mots</th>
                <th>Nombre d'occurences du mot cible</th>
                <th>Aspiration des pages</th>
                <th>Dump textuel</th>
                <th>Contexte</th>
                <th>Concordancier</th>

            </tr>
        </thead>
        <tbody>
EOF

while read -r LINE ; do
    if [[ $LINE =~ ^https?:// ]]; then

        NB_LIGNE=$(expr $NB_LIGNE + 1)

        CODE_ET_ENCODAGE=$(curl -s -L -i -o "tmp.txt" -w "%{http_code}\n%{content_type}" "$LINE")

        CODE=$(echo "$CODE_ET_ENCODAGE" | head -n 1)

        if [ $CODE -eq 0 ]; then
            echo "<tr><td>$NB_LIGNE</td><td>$LINE</td><td>ERREUR</td><td>ERREUR</td><td>ERREUR</td></tr>" >> "$SORTIE"
            continue
        fi

        ENCODAGE=$(echo "$CODE_ET_ENCODAGE" | grep -E -o "charset=.*")

        if [[ "$ENCODAGE" =~ ('UTF-8'|'utf-8') ]]; then
            ENCODAGE_OU_PAS="UTF-8"
        else
            ENCODAGE_OU_PAS="NON"
        fi
        # Compte du nombre de mots au total dans la page
        NB_MOTS=$(cat "tmp.txt" | lynx -dump -stdin -nolist | wc -w)

        # Aspiration des pages (1 fichier html par url)
        FICHIER_ASP=$"lang_fr-${NB_LIGNE}.html"
        CHEMIN=$"aspirations/$FICHIER_ASP"
        curl -s -L -o "$CHEMIN" "$LINE"
        ASPIRATION=$"<a href='aspirations/$FICHIER_ASP' target='_blank'>Aspiration n°$NB_LIGNE</a>"

        # Extraire le contenu textuel des pages 
        FICHIER_DUMP=$"dump/lang_fr-${NB_LIGNE}.txt"
        lynx -dump -nolist "$CHEMIN" > "$FICHIER_DUMP"
        DUMP=$"<a href='$FICHIER_DUMP' target='_blank'>Texte n°$NB_LIGNE</a>"

        # Compte du nombre du mot cible dans la page
        NB_OCCURENCES=$(grep -oEi "[a-zA-Z]*?charge[s]?" "$FICHIER_DUMP" | wc -l)

        # Contexte (quelques lignes autour du mot cible, "zoomer" dans le dump textuel)
        FICHIER_CONTX=$"contextes/lang_fr-${NB_LIGNE}.txt"
        grep -i -E -C 3 "charge[s]?" "$FICHIER_DUMP" | iconv -f ISO-8859-1 -t UTF-8 | sponge "$FICHIER_CONTX"
        CONTEXTE=$"<a href='$FICHIER_CONTX' target='_blank'>Contexte n°$NB_LIGNE</a>"

        # Concordancier (créer un fichier pour chaque URL à partir du contexte précédemment produit, construction de tableaux à mettre dans un dossier "Concordancier" et mettre les liens de chaque concordancier dans le tableau de base)
        FICHIER_CONCO=$"concordanciers/lang_fr-${NB_LIGNE}.html"
        cat > "$FICHIER_CONCO" <<EOF

<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.4/css/bulma.min.css"/>
    <link rel="stylesheet" href="../tableau.css"/>
</head>
<body>
    <div class="table-container">
        <h2>Concordancier</h2>
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
        # Extraction du contexte gauche/droit autour du motif cible avec grep et découpage dans ces contexres avec sed
        grep -E -i "([A-Za-z0-9_]+\W+){0,4}charge[s]?(\W+[A-Za-z0-9_]+){0,4}" "$FICHIER_CONTX" | sed -E -n "s/(.*)(charge[s]?)(.*)/<tr><td>\1<\/td><td>\2<\/td><td>\3<\/td><\/tr>/Ip" >> "$FICHIER_CONCO"

        cat >> "$FICHIER_CONCO" <<EOF
            </tbody>
        </table>
    </div>
</body>
</html>
EOF
        CONCORDANCIER=$"<a href='$FICHIER_CONCO' target='_blank'>Concordancier n°$NB_LIGNE</a>"

        # Tableau final avec toutes les infos
        echo "<tr><td>$NB_LIGNE</td><td id="url">$LINE</td><td>$CODE</td><td>$ENCODAGE_OU_PAS</td><td>$NB_MOTS</td><td>$NB_OCCURENCES</td><td>$ASPIRATION</td><td>$DUMP</td><td>$CONTEXTE</td><td>$CONCORDANCIER</td></tr>" >> "$SORTIE"

fi
done  < "$FICHIER_URLS"
cat >> "$SORTIE" <<EOF
        </tbody>
     </table>
    </div>
</body>
</html>
EOF