#!/usr/bin/env python3
"""Build the seasonal-produce and food-impact catalogues the Cuisine section ships with.

Two public datasets, both from ADEME and both under the Licence Ouverte 2.0:

- Impact CO2 "fruits et légumes de saison" (https://impactco2.fr/outils/fruitsetlegumes):
  for each fruit and vegetable, the months it is in season in France and its
  carbon footprint in kg CO2e per kg (Agribalyse 3.2).
- Agribalyse 3.2 synthèse (https://data.ademe.fr/datasets/agribalyse-31-synthese):
  the footprint of ~2,450 foods as sold in France, used for every ingredient that
  is not a fresh fruit or vegetable (meat, dairy, pasta, oil...).

What the datasets do not say is added here by hand and marked as such in the app:
the months Southern Europe (Spain, Italy, Portugal, Greece and their islands)
supplies each item, which items essentially only come from far away, and the
words and piece weights needed to read a recipe's ingredient list.

Run from the repository root, with network access:

    python3 Tools/food-data/build_food_data.py

It rewrites the two generated Swift files and fails loudly if a curated entry
points at a product or a slug the datasets no longer contain. Standard library
only.
"""

import csv
import io
import json
import sys
import urllib.request
from pathlib import Path

IMPACT_CO2_URL = "https://impactco2.fr/api/v1/fruitsetlegumes?month={month}"
AGRIBALYSE_URL = "https://data.ademe.fr/data-fair/api/v1/datasets/agribalyse-31-synthese/raw"
USER_AGENT = "Flaunedex/1.0 (https://github.com/Xelfe14/Faunedex)"

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Core/Sources/FlaunedexCore/Cuisine"
PRODUCE_OUT = CORE / "Saisons/ProduceCatalog+Data.swift"
FOOD_OUT = CORE / "Impact/FoodCatalog+Data.swift"

ALL_YEAR = list(range(1, 13))

# ---------------------------------------------------------------------------
# Curated: Southern Europe supply, far imports, and how recipes name each item.
#
# europe: months Spain, Italy, Portugal or Greece (with the Canaries, Madeira
#         and the Azores) supply the item in quantity. Indicative, from general
#         production calendars; the app says so.
# far:    the item essentially only reaches Paris from outside Europe. Months
#         ADEME lists for it are then shown as "import lointain".
# france: replaces ADEME's months when those describe harvests abroad rather
#         than in metropolitan France (ADEME lists bananas all year, for one).
# aliases: words that name the item in a recipe, singular, lower case. The
#         longest match wins, so "pomme" never swallows "pomme de terre".
# piece:  grams in one counted unit ("2 courgettes"), for recipe footprints.
# ---------------------------------------------------------------------------
PRODUCE = {
    # Fruits
    "abricot": dict(europe=[5, 6, 7, 8], origins="Espagne, Italie", aliases=["abricot"], piece=45),
    "ananas": dict(far=True, france=[], aliases=["ananas"], piece=1200,
                   note="Presque toujours importé de loin (Costa Rica, Côte d'Ivoire) ; les Açores en produisent un peu."),
    "banane": dict(france=[], europe=ALL_YEAR, origins="Canaries (Espagne), Madère (Portugal)",
                   aliases=["banane"], piece=120,
                   note="Aussi cultivée aux Antilles françaises, mais loin d'ici."),
    "carambole": dict(far=True, france=[], aliases=["carambole"], piece=100),
    "cassis": dict(aliases=["cassis"], piece=1),
    "cerise": dict(europe=[5, 6, 7], origins="Espagne, Italie", aliases=["cerise"], piece=8),
    "citron": dict(europe=ALL_YEAR, origins="Espagne, Italie",
                   aliases=["citron", "citron jaune", "jus de citron", "zeste de citron"], piece=100),
    "clementine": dict(europe=[10, 11, 12, 1, 2], origins="Espagne, Corse", aliases=["clementine"], piece=70),
    "coing": dict(europe=[9, 10, 11], origins="Espagne, Portugal", aliases=["coing"], piece=300),
    "datte": dict(far=True, france=[], aliases=["datte"], piece=8,
                  note="Vient surtout de Tunisie et d'Algérie."),
    "figue": dict(europe=[7, 8, 9, 10], origins="Espagne, Italie, Grèce", aliases=["figue"], piece=50),
    "fraise": dict(europe=[1, 2, 3, 4, 5, 6], origins="Espagne (Huelva)", aliases=["fraise"], piece=15),
    "framboise": dict(europe=[1, 2, 3, 4, 5, 10, 11, 12], origins="Espagne, Portugal (sous abri)",
                      aliases=["framboise"], piece=4),
    "fruitdelapassion": dict(far=True, france=[], aliases=["fruit de la passion", "maracuja"], piece=40,
                             note="Madère en produit un peu ; le reste vient de loin."),
    "grenade": dict(europe=[9, 10, 11, 12, 1], origins="Espagne", aliases=["grenade"], piece=300),
    "groseille": dict(aliases=["groseille"], piece=1),
    "kaki": dict(europe=[10, 11, 12, 1], origins="Espagne", aliases=["kaki", "plaquemine"], piece=200),
    "kiwi": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Italie, Grèce, Portugal", aliases=["kiwi"], piece=80),
    "mandarine": dict(europe=[10, 11, 12, 1, 2, 3], origins="Espagne", aliases=["mandarine"], piece=70),
    "mangue": dict(far=True, france=[], aliases=["mangue importee par avion", "mangue par avion"], piece=400,
                        note="Le fret aérien multiplie son empreinte par seize."),
    "manguebateau": dict(far=True, france=[], europe=[8, 9, 10, 11], origins="Espagne (Málaga)",
                         aliases=["mangue"], piece=400,
                         note="Le reste de l'année, importée de loin par bateau."),
    "melon": dict(europe=[5, 6, 7, 8, 9, 10], origins="Espagne", aliases=["melon"], piece=1000),
    "myrtille": dict(europe=[2, 3, 4, 5, 6], origins="Espagne, Portugal", aliases=["myrtille"], piece=1),
    "mure": dict(aliases=["mure"], piece=5),
    "nectarine": dict(europe=[5, 6, 7, 8, 9], origins="Espagne, Italie", aliases=["nectarine", "brugnon"], piece=150),
    "orange": dict(europe=[11, 12, 1, 2, 3, 4, 5, 6], origins="Espagne, Italie",
                   aliases=["orange", "jus d orange", "zeste d orange"], piece=200),
    "pamplemousse": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Espagne, Corse",
                         aliases=["pamplemousse", "pomelo"], piece=350),
    "pasteque": dict(europe=[5, 6, 7, 8, 9], origins="Espagne, Italie", aliases=["pasteque"], piece=4000),
    "poire": dict(europe=[7, 8, 9, 10, 11, 12, 1, 2, 3], origins="Italie, Espagne, Portugal",
                  aliases=["poire"], piece=150),
    "pomme": dict(europe=[8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6], origins="Italie (Trentin, Haut-Adige)",
                  aliases=["pomme"], piece=150),
    "prune": dict(europe=[6, 7, 8, 9], origins="Espagne, Italie", aliases=["prune", "mirabelle", "quetsche"], piece=40),
    "peche": dict(europe=[5, 6, 7, 8, 9], origins="Espagne, Italie", aliases=["peche"], piece=150),
    "raisin": dict(europe=[7, 8, 9, 10, 11], origins="Italie, Espagne", aliases=["raisin", "grain de raisin"], piece=300),
    "reineclaude": dict(aliases=["reine claude"], piece=30),
    "rhubarbe": dict(aliases=["rhubarbe"], piece=150),
    # Nuts
    "chataigne": dict(europe=[10, 11, 12], origins="Italie, Portugal, Espagne", aliases=["chataigne", "marron"], piece=10),
    "noisette": dict(aliases=["noisette"], piece=1.5),
    "noix": dict(aliases=["noix", "cerneau de noix"], piece=5),
    "noixdecoco": dict(far=True, france=[], aliases=["noix de coco", "coco rape", "coco rapee", "noix de coco rapee"], piece=500),
    # Herbs (ADEME files garlic here)
    "ail": dict(europe=[5, 6, 7], origins="Espagne", aliases=["ail", "tete d ail"], piece=50,
                units={"gousse": 5}),
    # Vegetables
    "artichaut": dict(europe=[11, 12, 1, 2, 3, 4, 5], origins="Italie, Espagne", aliases=["artichaut"], piece=300),
    "asperge": dict(europe=[2, 3, 4, 5, 6], origins="Espagne, Grèce", aliases=["asperge"], piece=20,
                    units={"botte": 500}),
    "aubergine": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5, 6], origins="Espagne (sous abri)",
                      aliases=["aubergine"], piece=300),
    "avocat": dict(france=[], europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Espagne (Málaga), Portugal (Algarve)",
                   far=True, aliases=["avocat"], piece=200,
                   note="De juin à septembre, importé de loin (Pérou, Kenya)."),
    "betterave": dict(aliases=["betterave"], piece=150),
    "blette": dict(aliases=["blette", "bette", "cote de blette"], piece=500, units={"botte": 500}),
    "brocoli": dict(europe=[10, 11, 12, 1, 2, 3, 4], origins="Espagne (Murcie)", aliases=["brocoli"], piece=400),
    "carotte": dict(europe=[4, 5, 6, 7, 8], origins="Espagne, Italie", aliases=["carotte"], piece=100,
                    units={"botte": 500}),
    "champignonmorille": dict(aliases=["morille"], piece=10),
    "chou": dict(aliases=["chou", "chou vert", "chou blanc", "chou rouge", "chou frise", "chou pointu"], piece=1000),
    "choudebruxelles": dict(aliases=["chou de bruxelles"], piece=15),
    "choufleur": dict(europe=[10, 11, 12, 1, 2, 3, 4], origins="Espagne, Italie", aliases=["chou fleur"], piece=800),
    "concombre": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Espagne (sous abri)",
                      aliases=["concombre"], piece=300),
    "courge": dict(aliases=["courge", "butternut", "courge butternut", "potimarron", "courge musquee"], piece=1000),
    "courgette": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Espagne (sous abri)",
                      aliases=["courgette"], piece=250),
    "cresson": dict(aliases=["cresson"], piece=150, units={"botte": 150}),
    "celeri": dict(aliases=["celeri", "celeri rave", "celeri branche", "branche de celeri"], piece=400),
    "endive": dict(aliases=["endive", "chicon"], piece=120),
    "fenouil": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Italie", aliases=["fenouil"], piece=250),
    "haricotvert": dict(europe=[10, 11, 12, 3, 4, 5], origins="Espagne (sous abri)",
                        aliases=["haricot vert", "haricot beurre", "haricot plat"], piece=None),
    "laitue": dict(europe=[10, 11, 12, 1, 2, 3, 4], origins="Espagne (Murcie)",
                   aliases=["laitue", "salade", "salade verte", "batavia", "feuille de chene", "sucrine", "romaine"],
                   piece=300),
    "mache": dict(aliases=["mache"], piece=None, units={"sachet": 100}),
    "navet": dict(aliases=["navet"], piece=100, units={"botte": 600}),
    "oignon": dict(europe=[4, 5, 6, 7, 8, 9], origins="Espagne",
                   aliases=["oignon", "oignon jaune", "oignon rouge", "oignon blanc", "oignon nouveau", "cebette"],
                   piece=100),
    "panais": dict(aliases=["panais"], piece=150),
    "petitpois": dict(europe=[2, 3, 4, 5], origins="Espagne, Italie", aliases=["petit pois"], piece=None),
    "poireau": dict(aliases=["poireau", "blanc de poireau"], piece=200),
    "poivron": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5, 6], origins="Espagne (sous abri)",
                    aliases=["poivron", "poivron rouge", "poivron vert", "poivron jaune"], piece=150),
    "potiron": dict(aliases=["potiron", "citrouille"], piece=1500),
    "radis": dict(aliases=["radis"], piece=10, units={"botte": 250}),
    "salsifis": dict(aliases=["salsifis"], piece=60),
    "tomate": dict(europe=[10, 11, 12, 1, 2, 3, 4, 5], origins="Espagne, Italie (sous abri l'hiver)",
                   aliases=["tomate", "tomate fraiche", "tomate grappe", "tomate coeur de boeuf"], piece=120),
    "echalote": dict(aliases=["echalote"], piece=30),
    "epinard": dict(aliases=["epinard", "pousse d epinard", "jeune pousse d epinard"], piece=None,
                    units={"botte": 300}),
    "topinambour": dict(aliases=["topinambour"], piece=60),
    "mais": dict(aliases=["mais", "epi de mais"], piece=250),
}

# Everything else a recipe uses, footprint from Agribalyse 3.2.
# (id, name shown, Agribalyse product, aliases, grams per piece, density g/ml, unit grams)
FOODS = [
    # Meat
    ("boeuf-hache", "Bœuf haché", "Bœuf, steak haché 15% MG, cru",
     ["boeuf hache", "steak hache", "viande hachee", "hache de boeuf", "viande de boeuf hachee"], 125, 1, {}),
    ("boeuf", "Bœuf", "Boeuf, à bourguignon ou pot-au-feu, cru",
     ["boeuf", "paleron", "joue de boeuf", "entrecote", "bavette", "faux filet", "rumsteck", "basse cote",
      "macreuse", "gite", "filet de boeuf", "onglet", "hampe", "pot au feu", "bourguignon", "cote de boeuf"],
     200, 1, {"tranche": 150}),
    ("veau", "Veau", "Veau, escalope, crue",
     ["veau", "escalope de veau", "tendron", "jarret de veau", "noix de veau", "quasi de veau"], 150, 1, {}),
    ("agneau", "Agneau", "Agneau, gigot, cru",
     ["agneau", "gigot", "souris d agneau", "cotelette d agneau", "epaule d agneau", "carre d agneau", "mouton"],
     150, 1, {}),
    ("porc", "Porc", "Porc, échine, crue",
     ["porc", "echine", "filet mignon", "cote de porc", "roti de porc", "poitrine de porc", "travers de porc",
      "palette de porc"], 150, 1, {"tranche": 120}),
    ("lardon", "Lardons", "Lardon fumé, cru", ["lardon", "lardon fume", "poitrine fumee", "bacon"], None, 1,
     {"tranche": 15}),
    ("jambon", "Jambon cuit", "Jambon cuit, choix",
     ["jambon", "jambon blanc", "jambon cuit", "jambon de paris"], 40, 1, {"tranche": 40}),
    ("jambon-cru", "Jambon cru", "Jambon cru",
     ["jambon cru", "jambon de bayonne", "jambon de parme", "prosciutto", "speck", "jambon serrano"], 15, 1,
     {"tranche": 15}),
    ("saucisse", "Saucisse", "Saucisse de Toulouse, crue",
     ["saucisse", "saucisse de toulouse", "chipolata", "merguez", "chair a saucisse", "saucisse fumee"],
     100, 1, {}),
    ("chorizo", "Chorizo", "Chorizo", ["chorizo"], None, 1, {"tranche": 5}),
    ("poulet", "Poulet (filet)", "Poulet, filet, sans peau, cru",
     ["poulet", "blanc de poulet", "filet de poulet", "escalope de poulet", "supreme de volaille", "volaille",
      "aiguillette de poulet"], 150, 1, {}),
    ("poulet-cuisse", "Poulet (cuisse)", "Poulet, cuisse, viande et peau, cru",
     ["cuisse de poulet", "haut de cuisse", "pilon de poulet", "pilon", "manchon de poulet"], 200, 1, {}),
    ("poulet-entier", "Poulet entier", "Poulet, viande et peau, cru",
     ["poulet entier", "poulet fermier", "poularde", "pintade"], 1500, 1, {}),
    ("dinde", "Dinde", "Dinde, escalope, crue", ["dinde", "escalope de dinde", "filet de dinde"], 120, 1, {}),
    ("magret", "Magret de canard", "Canard, magret, cru", ["magret", "magret de canard"], 350, 1, {}),
    ("canard", "Canard", "Canard, viande, crue", ["canard", "cuisse de canard", "confit de canard"], 250, 1, {}),
    ("lapin", "Lapin", "Lapin, viande crue", ["lapin", "rable de lapin", "cuisse de lapin"], 250, 1, {}),
    # Fish and seafood
    ("saumon", "Saumon", "Saumon, cru, élevage",
     ["saumon", "pave de saumon", "filet de saumon", "truite", "pave de truite"], 125, 1, {}),
    ("saumon-fume", "Saumon fumé", "Saumon fumé (emballage corrigé)", ["saumon fume", "truite fumee"], None, 1,
     {"tranche": 25}),
    ("cabillaud", "Poisson blanc", "Cabillaud, cru",
     ["cabillaud", "dos de cabillaud", "colin", "lieu", "lieu noir", "merlu", "poisson blanc", "eglefin",
      "haddock", "julienne", "lotte", "bar", "dorade", "sole", "merlan"], 150, 1, {}),
    ("thon", "Thon frais", "Thon, cru", ["thon", "thon frais", "steak de thon"], 150, 1, {}),
    ("thon-boite", "Thon en boîte", "Thon, au naturel, appertisé, égoutté",
     ["thon en boite", "thon au naturel", "miette de thon", "thon a l huile", "thon en conserve"], 140, 1, {}),
    ("sardine", "Sardine", "Sardine, crue", ["sardine"], 50, 1, {}),
    ("sardine-boite", "Sardines en boîte", "Sardine, à l'huile, appertisée, égouttée (emballage corrigé)",
     ["sardine a l huile", "sardine en boite"], 100, 1, {}),
    ("maquereau", "Maquereau", "Maquereau, cru", ["maquereau"], 300, 1, {}),
    ("crevette", "Crevettes", "Crevette, crue",
     ["crevette", "gambas", "crevette rose", "scampi", "langoustine"], 15, 1, {}),
    ("moule", "Moules", "Moule commune, crue", ["moule", "coque", "palourde"], 15, 1, {}),
    ("saint-jacques", "Saint-Jacques", "Coquille Saint-Jacques, noix, crue",
     ["saint jacques", "noix de saint jacques", "coquille saint jacques"], 25, 1, {}),
    ("anchois", "Anchois", "Anchois au sel (anchoité, semi-conserve)", ["anchois", "filet d anchois"], 4, 1, {}),
    # Eggs and dairy
    ("oeuf", "Œuf", "Oeuf, cru", ["oeuf", "oeuf entier", "oeuf frais"], 55, 1, {}),
    ("jaune-oeuf", "Jaune d'œuf", "Oeuf, jaune (jaune d'oeuf), cru", ["jaune d oeuf", "jaune"], 18, 1, {}),
    ("blanc-oeuf", "Blanc d'œuf", "Oeuf, blanc (blanc d'oeuf), cru", ["blanc d oeuf", "blanc en neige"], 35, 1, {}),
    ("lait", "Lait", "Lait demi-écrémé, UHT", ["lait", "lait demi ecreme", "lait ecreme"], None, 1.03, {}),
    ("lait-entier", "Lait entier", "Lait entier, UHT", ["lait entier"], None, 1.03, {}),
    ("beurre", "Beurre", "Beurre à 82% MG, doux",
     ["beurre", "beurre doux", "beurre demi sel", "beurre sale", "beurre mou", "beurre fondu", "noisette de beurre"],
     None, 0.95, {}),
    ("creme-epaisse", "Crème fraîche épaisse", "Crème de lait, 30% MG, épaisse, rayon frais",
     ["creme fraiche", "creme fraiche epaisse", "creme epaisse", "creme crue", "mascarpone"], None, 1, {}),
    ("creme-liquide", "Crème liquide", "Crème de lait, 30% MG, semi-épaisse, UHT",
     ["creme", "creme liquide", "creme entiere", "creme fleurette", "creme fraiche liquide", "creme liquide entiere"],
     None, 1, {}),
    ("creme-legere", "Crème légère", "Crème de lait, 15 à 20% MG, légère, semi-épaisse, UHT",
     ["creme legere", "creme fraiche legere", "creme allegee"], None, 1, {}),
    ("yaourt", "Yaourt nature", "Yaourt, lait fermenté ou spécialité laitière, nature",
     ["yaourt", "yogourt", "yaourt grec", "yaourt a la grecque", "skyr"], 125, 1, {}),
    ("fromage-blanc", "Fromage blanc", "Fromage blanc nature, 3% MG environ", ["fromage blanc", "faisselle"],
     None, 1, {}),
    ("fromage-frais", "Fromage frais", "Fromage frais type petit suisse, nature, 10% MG environ",
     ["fromage frais", "ricotta", "cream cheese", "saint moret", "philadelphia", "petit suisse", "carre frais"],
     None, 1, {}),
    ("emmental", "Emmental, comté", "Emmental ou emmenthal râpé",
     ["emmental", "gruyere", "comte", "fromage rape", "beaufort", "gouda", "abondance", "cantal", "tomme"],
     None, 0.4, {"tranche": 20}),
    ("parmesan", "Parmesan", "Parmesan",
     ["parmesan", "parmigiano", "parmigiano reggiano", "grana padano", "pecorino", "copeaux de parmesan"],
     None, 0.4, {}),
    ("mozzarella", "Mozzarella", "Mozzarella au lait de vache", ["mozzarella", "burrata", "boule de mozzarella"],
     125, 1, {}),
    ("chevre", "Fromage de chèvre", "Fromage de chèvre bûche",
     ["chevre", "fromage de chevre", "buche de chevre", "crottin de chevre", "chevre frais"], 60, 1,
     {"tranche": 20}),
    ("feta", "Feta", "Feta de brebis", ["feta"], 200, 1, {}),
    ("camembert", "Camembert, brie", "Camembert, sans précision", ["camembert", "brie", "coulommiers"], 250, 1, {}),
    ("roquefort", "Roquefort, bleu", "Roquefort", ["roquefort", "bleu", "gorgonzola", "fourme d ambert"], None, 1, {}),
    ("cheddar", "Cheddar", "Cheddar", ["cheddar"], None, 0.4, {"tranche": 20}),
    ("reblochon", "Reblochon", "Reblochon", ["reblochon"], 450, 1, {}),
    ("raclette", "Fromage à raclette", "Raclette (fromage)", ["raclette", "fromage a raclette", "morbier"], None, 1,
     {"tranche": 30}),
    # Cereals and doughs
    ("farine", "Farine de blé", "Farine de blé tendre ou froment T55 (pour pains)",
     ["farine", "farine de ble", "farine t45", "farine t55", "farine t65", "farine de ble t55"], None, 0.6, {}),
    ("farine-sarrasin", "Farine de sarrasin", "Farine de sarrasin", ["farine de sarrasin", "farine de ble noir"],
     None, 0.6, {}),
    ("farine-chataigne", "Farine de châtaigne", "Farine de châtaigne", ["farine de chataigne"], None, 0.6, {}),
    ("farine-riz", "Farine de riz", "Farine de riz", ["farine de riz"], None, 0.6, {}),
    ("farine-pois-chiche", "Farine de pois chiche", "Farine de pois chiche", ["farine de pois chiche"], None, 0.6, {}),
    ("fecule", "Fécule de maïs", "Amidon de maïs ou fécule de maïs",
     ["maizena", "fecule", "fecule de mais", "amidon de mais", "fecule de pomme de terre"], None, 0.6, {}),
    ("pates", "Pâtes sèches", "Pâtes sèches standard, crues",
     ["pate", "pate seche", "spaghetti", "tagliatelle", "penne", "fusilli", "linguine", "macaroni", "coquillette",
      "farfalle", "rigatoni", "lasagne", "feuille de lasagne", "orzo", "conchiglie", "pappardelle"], None, 1, {}),
    ("pates-fraiches", "Pâtes fraîches", "Pâtes fraîches, aux œufs, crues",
     ["pate fraiche", "tagliatelle fraiche", "gnocchi"], None, 1, {}),
    ("nouilles", "Nouilles asiatiques", "Nouilles asiatiques cuites, nature, non salées",
     ["nouille", "nouille de ble", "udon", "ramen", "nouille chinoise"], None, 1, {}),
    ("vermicelle-riz", "Vermicelles de riz", "Vermicelle de riz, sèche",
     ["vermicelle de riz", "nouille de riz", "vermicelle"], None, 1, {}),
    ("riz", "Riz", "Riz blanc, cru",
     ["riz", "riz basmati", "riz arborio", "riz rond", "riz complet", "riz thai", "riz a risotto", "riz carnaroli"],
     None, 0.85, {}),
    ("semoule", "Semoule, couscous", "Couscous (semoule de blé dur roulée précuite à la vapeur), crue",
     ["semoule", "couscous", "semoule de ble"], None, 0.75, {}),
    ("boulgour", "Boulgour", "Boulgour de blé, cru", ["boulgour", "bulgur"], None, 0.75, {}),
    ("quinoa", "Quinoa", "Quinoa, cru", ["quinoa"], None, 0.75, {}),
    ("polenta", "Polenta", "Polenta ou semoule de maïs, précuite, sèche", ["polenta", "semoule de mais"], None, 0.75, {}),
    ("avoine", "Flocons d'avoine", "Flocon d'avoine", ["flocon d avoine", "avoine"], None, 0.4, {}),
    ("pain", "Pain", "Pain courant français, 400g ou boule",
     ["pain", "baguette", "pain de campagne", "pain rassis", "chapelure", "crouton", "pain complet"], 250, 0.3,
     {"tranche": 35}),
    ("pain-de-mie", "Pain de mie", "Pain de mie, courant", ["pain de mie", "pain burger", "pain a burger"], None, 1,
     {"tranche": 25}),
    ("pate-feuilletee", "Pâte feuilletée", "Pâte feuilletée pur beurre, crue",
     ["pate feuilletee", "rouleau de pate feuilletee"], 230, 1, {}),
    ("pate-brisee", "Pâte brisée", "Pâte brisée, pur beurre, crue", ["pate brisee"], 230, 1, {}),
    ("pate-sablee", "Pâte sablée", "Pâte sablée pur beurre, crue", ["pate sablee"], 230, 1, {}),
    ("pate-pizza", "Pâte à pizza", "Pâte à pizza crue", ["pate a pizza"], 260, 1, {}),
    ("brick", "Feuilles de brick", "Khatfa feuille de brick, préemballée", ["feuille de brick", "brick", "pate filo"],
     None, 1, {"feuille": 12}),
    # Pulses and plant proteins
    ("lentille", "Lentilles", "Lentille verte, sèche",
     ["lentille", "lentille corail", "lentille verte", "lentille du puy", "lentille blonde", "lentille beluga"],
     None, 0.85, {}),
    ("pois-chiche", "Pois chiches secs", "Pois chiche, sec", ["pois chiche", "pois chiche sec"], None, 0.85, {}),
    ("pois-chiche-cuit", "Pois chiches en conserve", "Pois chiche, appertisé, égoutté",
     ["pois chiche cuit", "pois chiche en conserve", "pois chiche egoutte", "pois chiche en boite"], 265, 1, {}),
    ("haricot-blanc", "Haricots blancs", "Haricot blanc, sec", ["haricot blanc", "lingot", "haricot coco", "flageolet"],
     None, 0.85, {}),
    ("haricot-rouge", "Haricots rouges", "Haricot rouge, sec", ["haricot rouge", "haricot noir"], None, 0.85, {}),
    ("haricot-conserve", "Haricots en conserve", "Haricot rouge, appertisé, égoutté",
     ["haricot rouge en conserve", "haricot blanc en conserve", "haricot rouge cuit", "haricot blanc cuit"],
     250, 1, {}),
    ("pois-casse", "Pois cassés", "Pois cassé, sec", ["pois casse"], None, 0.85, {}),
    ("feve", "Fèves", "Fève à écosser, fraîche", ["feve"], None, 1, {}),
    ("tofu", "Tofu", "Tofu, nature", ["tofu", "tofu ferme", "tofu soyeux"], 200, 1, {}),
    # Potatoes and roots outside the ADEME calendar
    ("pomme-de-terre", "Pomme de terre", "Pomme de terre, sans peau, crue",
     ["pomme de terre", "patate", "pomme de terre a chair ferme", "grenaille", "pomme de terre farineuse"],
     150, 1, {}),
    ("pomme-de-terre-nouvelle", "Pomme de terre nouvelle", "Pomme de terre nouvelle, crue",
     ["pomme de terre nouvelle", "pomme de terre primeur"], 60, 1, {}),
    ("patate-douce", "Patate douce", "Patate douce, crue", ["patate douce"], 300, 1, {}),
    ("gingembre", "Gingembre", "Gingembre, racine crue", ["gingembre", "gingembre frais"], 20, 1, {}),
    ("gingembre-poudre", "Gingembre en poudre", "Gingembre, poudre", ["gingembre en poudre"], None, 0.5, {}),
    ("citron-vert", "Citron vert", "Citron vert ou Lime, pulpe, cru",
     ["citron vert", "lime", "jus de citron vert", "zeste de citron vert"], 70, 1, {}),
    ("mais-doux", "Maïs doux en conserve", "Maïs doux, appertisé, égoutté",
     ["mais doux", "mais en conserve", "mais en boite"], 285, 1, {}),
    # Fats
    ("huile-olive", "Huile d'olive", "Huile d'olive vierge extra",
     ["huile d olive", "huile olive", "huile d olive vierge extra"], None, 0.92, {}),
    ("huile-tournesol", "Huile de tournesol", "Huile de tournesol", ["huile de tournesol"], None, 0.92, {}),
    ("huile-colza", "Huile de colza", "Huile de colza", ["huile de colza"], None, 0.92, {}),
    ("huile", "Huile", "Huile combinée (mélange d'huiles)",
     ["huile", "huile neutre", "huile vegetale", "huile de pepin de raisin", "huile de friture"], None, 0.92, {}),
    ("huile-sesame", "Huile de sésame", "Huile de sésame", ["huile de sesame"], None, 0.92, {}),
    ("huile-coco", "Huile de coco", "Huile de coco", ["huile de coco"], None, 0.92, {}),
    # Sugar and sweet things
    ("sucre", "Sucre", "Sucre blanc",
     ["sucre", "sucre en poudre", "sucre semoule", "sucre glace", "sucre blanc", "sucre de canne"], None, 0.85, {}),
    ("sucre-roux", "Sucre roux", "Sucre roux", ["sucre roux", "cassonade", "vergeoise", "sucre complet"], None, 0.85, {}),
    ("sucre-vanille", "Sucre vanillé", "Sucre vanillé", ["sucre vanille"], None, 0.85, {"sachet": 7.5}),
    ("miel", "Miel", "Miel", ["miel"], None, 1.4, {}),
    ("sirop-erable", "Sirop d'érable", "Sirop d'érable", ["sirop d erable"], None, 1.3, {}),
    ("chocolat", "Chocolat noir", "Chocolat noir à 40% de cacao minimum, à pâtisser, tablette",
     ["chocolat", "chocolat noir", "chocolat patissier", "chocolat a patisser", "pepite de chocolat",
      "chocolat au lait", "chocolat blanc"], None, 1, {"tablette": 200}),
    ("chocolat-70", "Chocolat noir 70 %", "Chocolat noir à 70% cacao minimum, extra, dégustation, tablette",
     ["chocolat noir 70", "chocolat a 70", "chocolat noir a 70"], None, 1, {}),
    ("cacao", "Cacao en poudre", "Cacao, non sucré, poudre soluble",
     ["cacao", "cacao en poudre", "cacao non sucre"], None, 0.5, {}),
    ("confiture", "Confiture", "Confiture d'abricot (extra ou classique)", ["confiture"], None, 1.3, {}),
    ("creme-marrons", "Crème de marrons", "Crème de marrons", ["creme de marron"], None, 1.3, {}),
    ("raisin-sec", "Raisins secs", "Raisin, sec", ["raisin sec"], None, 0.6, {}),
    ("pruneau", "Pruneaux", "Pruneau, sec", ["pruneau"], 10, 1, {}),
    ("vanille", "Vanille", "Vanille, extrait aqueux",
     ["vanille", "extrait de vanille", "gousse de vanille", "arome vanille"], 3, 1, {"gousse": 3}),
    ("gelatine", "Gélatine", "Gélatine, sèche", ["gelatine", "feuille de gelatine", "agar agar"], None, 1,
     {"feuille": 2}),
    ("levure", "Levure", "Levure chimique ou Poudre à lever",
     ["levure", "levure chimique", "poudre a lever", "levure boulangere", "bicarbonate"], None, 0.9,
     {"sachet": 11}),
    # Nuts and seeds outside the ADEME calendar
    ("amande", "Amandes", "Amande, mondée, émondée ou blanchie",
     ["amande", "poudre d amande", "amande effilee", "amande en poudre", "amande entiere", "pate d amande"], 1.2, 0.45, {}),
    ("cajou", "Noix de cajou", "Noix de cajou, grillée, salée", ["noix de cajou", "cajou"], 1.5, 0.5, {}),
    ("pignon", "Pignons de pin", "Pignon de pin", ["pignon", "pignon de pin"], None, 0.5, {}),
    ("cacahuete", "Cacahuètes", "Cacahuète ou Arachide", ["cacahuete", "arachide"], None, 0.5, {}),
    ("beurre-cacahuete", "Beurre de cacahuète", "Beurre de cacahuète ou Pâte d'arachide",
     ["beurre de cacahuete", "beurre d arachide", "pate d arachide"], None, 1, {}),
    ("pistache", "Pistaches", "Pistache, grillée", ["pistache"], None, 0.5, {}),
    ("noix-pecan", "Noix de pécan", "Noix de pécan", ["noix de pecan"], None, 0.5, {}),
    ("sesame", "Sésame", "Sésame, graine", ["sesame", "graine de sesame"], None, 0.6, {}),
    # Herbs and spices
    ("persil", "Persil", "Persil, frais", ["persil", "persil plat", "persil frise"], None, 0.2,
     {"brin": 1, "botte": 50, "feuille": 0.2}),
    ("basilic", "Basilic", "Basilic, frais", ["basilic"], None, 0.2, {"brin": 1, "botte": 30, "feuille": 0.3}),
    ("coriandre", "Coriandre", "Coriandre, fraiche", ["coriandre", "coriandre fraiche"], None, 0.2,
     {"brin": 1, "botte": 30, "feuille": 0.1}),
    ("menthe", "Menthe", "Menthe, fraîche", ["menthe", "menthe fraiche"], None, 0.2,
     {"brin": 1, "botte": 30, "feuille": 0.2}),
    ("herbes", "Herbes fraîches", "Basilic, frais",
     ["ciboulette", "cerfeuil", "aneth", "estragon", "sauge", "origan frais", "herbe fraiche", "fines herbes",
      "thym", "romarin"], None, 0.2, {"brin": 1, "botte": 30, "feuille": 0.2}),
    ("herbes-sechees", "Herbes séchées", "Thym, séché",
     ["herbe de provence", "thym seche", "origan", "origan seche", "romarin seche"], None, 0.3, {}),
    ("laurier", "Laurier", "Laurier, feuille", ["laurier", "feuille de laurier"], None, 0.2, {"feuille": 0.2}),
    ("sel", "Sel", "Sel blanc alimentaire, non iodé, non fluoré (marin, ignigène ou gemme)",
     ["sel", "fleur de sel", "gros sel", "sel fin"], None, 1.2, {}),
    ("poivre", "Poivre", "Poivre noir, poudre", ["poivre", "poivre noir", "poivre blanc", "poivre du moulin"],
     None, 0.5, {}),
    ("epices", "Épices", "Cumin, graine",
     ["cumin", "curry", "paprika", "cannelle", "curcuma", "piment", "piment d espelette", "ras el hanout",
      "quatre epices", "coriandre en poudre", "garam masala", "piment de cayenne", "cardamome"], None, 0.5, {}),
    ("muscade", "Noix de muscade", "Noix de muscade", ["muscade", "noix de muscade"], None, 0.5, {}),
    # Condiments and pantry
    ("bouillon", "Bouillon", "Bouillon de volaille, déshydraté reconstitué",
     ["bouillon", "bouillon de volaille", "bouillon de legume", "bouillon de boeuf", "fond de volaille",
      "fond de veau", "cube de bouillon", "bouillon cube", "bouillon de poulet"], 500, 1, {}),
    ("sauce-soja", "Sauce soja", "Sauce soja, préemballée", ["sauce soja", "soja", "tamari"], None, 1.1, {}),
    ("moutarde", "Moutarde", "Moutarde", ["moutarde", "moutarde a l ancienne", "moutarde de dijon"], None, 1, {}),
    ("vinaigre", "Vinaigre", "Vinaigre",
     ["vinaigre", "vinaigre balsamique", "vinaigre de vin", "vinaigre de xeres", "vinaigre de riz"], None, 1, {}),
    ("vinaigre-cidre", "Vinaigre de cidre", "Vinaigre de cidre", ["vinaigre de cidre"], None, 1, {}),
    ("concentre-tomate", "Concentré de tomate", "Tomate, concentré, appertisé",
     ["concentre de tomate", "double concentre de tomate", "puree de tomate concentree"], None, 1.1, {}),
    ("tomate-conserve", "Tomates en conserve", "Tomate, pulpe, appertisée",
     ["tomate pelee", "tomate concassee", "pulpe de tomate", "tomate en conserve", "tomate en boite",
      "chair de tomate", "tomate en des"], 400, 1, {}),
    ("coulis-tomate", "Coulis de tomate", "Tomate, coulis, appertisé (purée de tomates mi-réduite à 11%)",
     ["coulis de tomate", "passata", "sauce tomate", "puree de tomate", "tomate frito"], None, 1.05, {}),
    ("olive", "Olives", "Olives vertes, fourrées ou farcies (anchois, poivrons, etc.)",
     ["olive", "olive noire", "olive verte", "olive de kalamata", "tapenade"], 4, 1, {}),
    ("lait-coco", "Lait de coco", "Lait de coco ou Crème de coco", ["lait de coco", "creme de coco"], None, 1, {}),
    ("mayonnaise", "Mayonnaise", "Mayonnaise (70% MG min.)", ["mayonnaise"], None, 0.95, {}),
    ("ketchup", "Ketchup", "Ketchup", ["ketchup"], None, 1.1, {}),
    ("boisson-amande", "Boisson à l'amande", "Boisson à l'amande", ["lait d amande", "boisson a l amande"], None, 1, {}),
    ("boisson-avoine", "Boisson à l'avoine", "Boisson à base d'avoine, nature",
     ["lait d avoine", "boisson a l avoine", "boisson vegetale"], None, 1, {}),
    ("boisson-soja", "Boisson au soja", "Boisson au soja, nature", ["lait de soja", "boisson au soja"], None, 1, {}),
    # Drinks used in cooking
    ("vin-blanc", "Vin blanc", "Vin blanc sec", ["vin blanc", "vin blanc sec"], None, 1, {}),
    ("vin-rouge", "Vin rouge", "Vin rouge", ["vin", "vin rouge"], None, 1, {}),
    ("biere", "Bière", "Bière \"coeur de marché\" (4-5° alcool)", ["biere"], 330, 1, {}),
    ("cidre", "Cidre", "Cidre brut", ["cidre"], None, 1, {}),
    ("rhum", "Rhum", "Rhum", ["rhum", "cognac", "armagnac", "calvados", "porto", "kirsch", "cointreau",
                              "grand marnier", "whisky"], None, 1, {}),
    ("cafe", "Café", "Café, non instantané, non sucré, prêt à boire",
     ["cafe", "expresso", "espresso", "cafe fort"], None, 1, {}),
    ("cafe-moulu", "Café moulu", "Café, moulu", ["cafe moulu", "cafe soluble"], None, 0.4, {}),
    ("the", "Thé", "Thé infusé, non sucré", ["the", "the vert", "the noir"], None, 1, {}),
    ("eau", "Eau", None, ["eau", "eau froide", "eau chaude", "eau tiede", "glacon", "eau bouillante"], None, 1, {}),
]

UNIT_KEYS = {  # French unit words used above -> MetricUnit case names in Swift
    "gousse": "clove", "brin": "sprig", "botte": "bunch", "tranche": "slice",
    "feuille": "leaf", "sachet": "packet", "tablette": None,
}

CATEGORY = {
    "fruits": "fruit",
    "fruits à coque et graines oléagineuses": "nut",
    "légumes": "vegetable",
    "herbes": "vegetable",
    "pommes de terre et autres tubercules": "vegetable",
    "pâtes, riz et céréales": "vegetable",
}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def swift_months(months):
    return "[" + ", ".join(str(m) for m in sorted(set(months))) + "]"


def swift_double(x):
    return repr(round(float(x), 4))


def swift_units(units):
    pairs = []
    for word, grams in units.items():
        case = UNIT_KEYS.get(word)
        if case is None:
            continue
        pairs.append(f".{case}: {swift_double(grams)}")
    return "[" + ", ".join(pairs) + "]" if pairs else "[:]"


def main():
    # Impact CO2: one request per month; every item carries its full month list.
    produce = {}
    for month in range(1, 13):
        for item in json.loads(fetch(IMPACT_CO2_URL.format(month=month)))["data"]:
            produce[item["slug"]] = item
    missing = sorted(set(produce) - set(PRODUCE))
    unknown = sorted(set(PRODUCE) - set(produce))
    if missing or unknown:
        sys.exit(f"Curated produce out of date. Not curated: {missing}. Gone from Impact CO2: {unknown}")

    rows = csv.DictReader(io.StringIO(fetch(AGRIBALYSE_URL).decode("utf-8")))
    agribalyse = {r["Nom du Produit en Français"]: float(r["Changement climatique"])
                  for r in rows if r["Nom du Produit en Français"]}
    for food in FOODS:
        if food[2] is not None and food[2] not in agribalyse:
            sys.exit(f"Agribalyse no longer has {food[2]!r} (food {food[0]})")

    produce_lines, produce_foods = [], []
    order = sorted(produce.values(), key=lambda p: p["name"])
    for item in order:
        slug, extra = item["slug"], PRODUCE[item["slug"]]
        france = extra.get("france", item["months"])
        if extra.get("far") and "france" not in extra:
            france = []
        produce_lines.append(
            "        Produce(\n"
            f"            id: {swift_string(slug)}, name: {swift_string(item['name'])},\n"
            f"            category: .{CATEGORY[item['category']]},\n"
            f"            franceMonths: {swift_months(france)},\n"
            f"            europeMonths: {swift_months(extra.get('europe', []))},\n"
            f"            availableMonths: {swift_months(item['months'])},\n"
            f"            farImport: {'true' if extra.get('far') else 'false'},\n"
            f"            origins: {swift_string(extra['origins']) if extra.get('origins') else 'nil'},\n"
            f"            note: {swift_string(extra['note']) if extra.get('note') else 'nil'},\n"
            f"            kgCO2ePerKg: {swift_double(item['ecv'])}\n"
            "        ),"
        )
        piece = extra.get("piece")
        produce_foods.append(
            "        Food(\n"
            f"            id: {swift_string('produce:' + slug)}, name: {swift_string(item['name'])},\n"
            f"            aliases: [{', '.join(swift_string(a) for a in extra['aliases'])}],\n"
            f"            kgCO2ePerKg: {swift_double(item['ecv'])},\n"
            f"            source: {swift_string('Impact CO2 (ADEME) : ' + item['name'])},\n"
            f"            produceID: {swift_string(slug)},\n"
            f"            gramsPerPiece: {swift_double(piece) if piece else 'nil'},\n"
            f"            gramsPerMilliliter: 1,\n"
            f"            unitGrams: {swift_units(extra.get('units', {}))}\n"
            "        ),"
        )

    food_lines = []
    for (fid, name, product, aliases, piece, density, units) in FOODS:
        co2 = agribalyse[product] if product else 0.0
        source = f"Agribalyse 3.2 : {product}" if product else "Sans impact notable"
        food_lines.append(
            "        Food(\n"
            f"            id: {swift_string(fid)}, name: {swift_string(name)},\n"
            f"            aliases: [{', '.join(swift_string(a) for a in aliases)}],\n"
            f"            kgCO2ePerKg: {swift_double(co2)},\n"
            f"            source: {swift_string(source)},\n"
            "            produceID: nil,\n"
            f"            gramsPerPiece: {swift_double(piece) if piece else 'nil'},\n"
            f"            gramsPerMilliliter: {swift_double(density)},\n"
            f"            unitGrams: {swift_units(units)}\n"
            "        ),"
        )

    header = ("// Generated by Tools/food-data/build_food_data.py. Do not edit by hand:\n"
              "// change the curated tables in the script and run it again.\n\n")
    PRODUCE_OUT.parent.mkdir(parents=True, exist_ok=True)
    PRODUCE_OUT.write_text(
        header +
        "extension ProduceCatalog {\n"
        "    /// Impact CO2 (ADEME) seasonal calendar and footprints, Agribalyse 3.2,\n"
        "    /// Licence Ouverte 2.0; Southern Europe months, far imports and notes curated.\n"
        "    public static let all: [Produce] = [\n" + "\n".join(produce_lines) + "\n    ]\n}\n"
    )
    FOOD_OUT.parent.mkdir(parents=True, exist_ok=True)
    FOOD_OUT.write_text(
        header +
        "extension FoodCatalog {\n"
        "    /// Fresh produce: footprint from Impact CO2 (ADEME), so a vegetable shows\n"
        "    /// the same figure in the calendar and in a recipe.\n"
        "    static let produceFoods: [Food] = [\n" + "\n".join(produce_foods) + "\n    ]\n\n"
        "    /// Everything else: footprint from Agribalyse 3.2 (ADEME, Licence Ouverte 2.0).\n"
        "    static let pantryFoods: [Food] = [\n" + "\n".join(food_lines) + "\n    ]\n}\n"
    )
    print(f"{len(order)} produce items, {len(FOODS)} pantry foods written.")


if __name__ == "__main__":
    main()
