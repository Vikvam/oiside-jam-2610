class_name House
extends RefCounted
## Static description of the house: rooms, doors, sound features, objects.
## Everybody knows the layout and the room names. Objects are only known to
## whoever has been in the room (the rescuer knows them all). Nicknames are
## childhood memories shared only by the player and the rescuer.

const FEATURES := ["clock", "fan", "rain", "radiator"]
const FEATURE_LABEL := {
	"clock": "ticking clock",
	"fan": "humming fan",
	"rain": "rain on a window",
	"radiator": "clanking radiator",
}
const DIRS := ["north", "east", "south", "west"]
const DIR_VEC := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}

## rect is in plan units (the plan is 12 x 9 units).
## features: what the room CAN sound like. "rain" means it has a window.
const ROOMS := [
	{
		"id": "library", "name": "Library", "rect": [0, 0, 4, 3], "phone": true,
		"features": ["clock", "rain"],
		"objects": [
			{"id": "bookcase", "name": "tall bookcase", "keys": ["bookcase", "bookshelf", "shelf", "shelves", "books"],
				"desc": "A tall bookcase. One volume is missing, leaving a dark gap."},
			{"id": "globe", "name": "old globe", "keys": ["globe", "world", "map"],
				"desc": "A dusty globe. Someone drew a tiny skull on Bohemia."},
			{"id": "armchair", "name": "leather armchair", "keys": ["armchair", "leather", "chair"],
				"desc": "A cracked leather armchair, still warm-looking somehow."},
		],
	},
	{
		"id": "study", "name": "Study", "rect": [4, 0, 4, 3], "phone": true,
		"features": ["clock", "fan"],
		"objects": [
			{"id": "desk", "name": "heavy oak desk", "keys": ["desk", "oak", "drawer", "drawers"],
				"desc": "A heavy oak desk. The drawers are locked."},
			{"id": "horse_painting", "name": "painting of a horse", "keys": ["painting", "horse", "portrait", "picture", "frame"],
				"desc": "A painting of a grey horse.", "nick": "Captain",
				"memory": "A grey horse in a gilt frame... Captain. You used to salute him every morning."},
			{"id": "typewriter", "name": "typewriter", "keys": ["typewriter", "typing", "keys"],
				"desc": "A black typewriter with a half-written letter in it."},
		],
	},
	{
		"id": "nursery", "name": "Nursery", "rect": [8, 0, 4, 3], "phone": false,
		"features": ["rain", "radiator"],
		"objects": [
			{"id": "bear", "name": "stuffed bear", "keys": ["bear", "teddy", "stuffed", "toy"],
				"desc": "A stuffed bear with one button eye.", "nick": "Mr. Buttons",
				"memory": "A one-eyed stuffed bear... Mr. Buttons! He used to guard your bed."},
			{"id": "rocking_horse", "name": "rocking horse", "keys": ["rocking", "horse"],
				"desc": "A wooden rocking horse. It creaks when you look at it."},
			{"id": "dollhouse", "name": "dollhouse", "keys": ["dollhouse", "dolls", "doll", "miniature"],
				"desc": "A dollhouse — a tiny copy of this very house."},
		],
	},
	{
		"id": "parlor", "name": "Parlor", "rect": [0, 3, 4, 3], "phone": true,
		"features": ["clock", "radiator"],
		"objects": [
			{"id": "piano", "name": "grand piano", "keys": ["piano", "keys", "grand"],
				"desc": "Grandma's grand piano, lid closed."},
			{"id": "fireplace", "name": "fireplace", "keys": ["fireplace", "fire", "hearth", "chimney", "mantel"],
				"desc": "A cold fireplace full of grey ash."},
			{"id": "mirror", "name": "tall mirror", "keys": ["mirror", "reflection"],
				"desc": "A tall mirror. You don't look at it for long."},
		],
	},
	{
		"id": "hall", "name": "Hall", "rect": [4, 3, 4, 3], "phone": true,
		"features": ["clock", "rain"],
		"objects": [
			{"id": "stag", "name": "stag head", "keys": ["stag", "antlers", "deer", "trophy"],
				"desc": "A mounted stag head with glass eyes.", "nick": "Old Gregor",
				"memory": "The stag head... Old Gregor. You both swore he blinked once."},
			{"id": "staircase", "name": "staircase", "keys": ["stairs", "staircase", "steps", "banister"],
				"desc": "A broad staircase. The upstairs is boarded off."},
			{"id": "umbrella_stand", "name": "umbrella stand", "keys": ["umbrella", "umbrellas", "stand", "cane"],
				"desc": "An umbrella stand made from an elephant's foot. Grim."},
		],
	},
	{
		"id": "kitchen", "name": "Kitchen", "rect": [8, 3, 4, 3], "phone": true,
		"features": ["fan", "rain", "radiator"],
		"objects": [
			{"id": "stove", "name": "iron stove", "keys": ["stove", "oven", "iron", "cooker"],
				"desc": "A big iron stove. The floorboards in front of it are loose."},
			{"id": "dumbwaiter", "name": "dumbwaiter", "keys": ["dumbwaiter", "hatch", "shaft"],
				"desc": "A dumbwaiter hatch in the wall.", "nick": "the ghost lift",
				"memory": "The dumbwaiter... the ghost lift. You rode it once and got stuck for an hour."},
			{"id": "knife_block", "name": "knife block", "keys": ["knife", "knives", "block"],
				"desc": "A knife block. One slot is empty. You try not to think about it."},
		],
	},
	{
		"id": "conservatory", "name": "Conservatory", "rect": [0, 6, 4, 3], "phone": false,
		"features": ["rain"],
		"objects": [
			{"id": "birdcage", "name": "empty birdcage", "keys": ["birdcage", "cage", "bird", "canary"],
				"desc": "An empty brass birdcage.", "nick": "Pip's palace",
				"memory": "The brass birdcage... Pip's palace. Pip was the canary. You buried him by the roses."},
			{"id": "fern", "name": "dead fern", "keys": ["fern", "plant", "plants", "pot"],
				"desc": "A huge dead fern in a cracked pot."},
			{"id": "wicker_chair", "name": "wicker chair", "keys": ["wicker", "chair"],
				"desc": "A wicker chair, rocking slightly. There is no wind."},
		],
	},
	{
		"id": "dining", "name": "Dining Room", "rect": [4, 6, 4, 3], "phone": true,
		"features": ["fan", "radiator"],
		"objects": [
			{"id": "long_table", "name": "long table", "keys": ["table", "tablecloth", "dinner"],
				"desc": "A long table set for twelve. Nobody has eaten here in years."},
			{"id": "china_cabinet", "name": "china cabinet", "keys": ["cabinet", "china", "plates", "porcelain", "cups"],
				"desc": "A cabinet of porcelain. Every cup has a chip."},
			{"id": "chandelier", "name": "chandelier", "keys": ["chandelier", "crystal", "crystals"],
				"desc": "A crystal chandelier, swaying very slightly."},
		],
	},
	{
		"id": "pantry", "name": "Pantry", "rect": [8, 6, 4, 3], "phone": false,
		"features": ["radiator"],
		"objects": [
			{"id": "jam_shelf", "name": "shelf of jam jars", "keys": ["jam", "jars", "jar", "preserves"],
				"desc": "Shelves of jam jars, labelled in a shaky hand: 1987, 1988, 1989..."},
			{"id": "flour_sacks", "name": "flour sacks", "keys": ["flour", "sacks", "sack", "bags"],
				"desc": "A pile of flour sacks. Something small has nested in them."},
			{"id": "meat_hook", "name": "meat hook", "keys": ["hook", "hooks", "meat"],
				"desc": "A rusty meat hook on a rail. It is empty. Thankfully."},
		],
	},
]

const DOORS := [
	["library", "study"], ["study", "nursery"],
	["library", "parlor"], ["study", "hall"], ["nursery", "kitchen"],
	["parlor", "hall"], ["hall", "kitchen"],
	["parlor", "conservatory"], ["hall", "dining"], ["kitchen", "pantry"],
	["dining", "pantry"],
]

## How each exit spot opens. Only the rescuer knows this.
const EXIT_FLAVOR := {
	"bookcase": "pull the missing-volume gap and the bookcase swings out onto old servants' stairs",
	"globe": "the globe's base is a hatch to a crawlspace that runs under the garden",
	"armchair": "under the armchair a trapdoor drops into the old coal tunnel",
	"desk": "the knee-hole of the desk has a false back into a passage",
	"horse_painting": "behind Captain the horse there is a small door into the wall passage",
	"typewriter": "the typewriter table hides a floor hatch",
	"bear": "Mr. Buttons sits on a loose panel that opens to a chute",
	"rocking_horse": "under the rocking horse is a trapdoor",
	"dollhouse": "the dollhouse wall panel behind it is a hidden door",
	"piano": "under the piano the floorboards lift to a tunnel",
	"fireplace": "the back plate of the fireplace slides into a chimney passage",
	"mirror": "the mirror is a door, push its left edge",
	"stag": "pull Old Gregor's left antler and a panel opens",
	"staircase": "the cupboard under the stairs has a false floor",
	"umbrella_stand": "behind the umbrella stand a low panel opens",
	"stove": "the loose floorboards in front of the stove open to the cellar",
	"dumbwaiter": "the dumbwaiter shaft goes down to the coal tunnel",
	"knife_block": "the tiled wall behind the knife block is a hatch",
	"birdcage": "the birdcage hook is a lever for a glass door in the garden wall",
	"fern": "the fern pot hides a drain cover big enough to crawl through",
	"wicker_chair": "under the wicker chair a grate opens",
	"long_table": "under the long table a trapdoor",
	"china_cabinet": "the china cabinet swings out on hinges",
	"chandelier": "the chandelier chain is a pull that opens a wall panel",
	"jam_shelf": "the jam shelf swings out into the old ice cellar",
	"flour_sacks": "under the flour sacks is a hatch",
	"meat_hook": "pull the meat hook down and the back wall opens",
}

## The large house adds a fourth column.
const EXTRA_ROOMS := [
	{
		"id": "billiard", "name": "Billiard Room", "rect": [12, 0, 4, 3], "phone": true,
		"features": ["fan"],
		"objects": [
			{"id": "billiard_table", "name": "billiard table", "keys": ["billiard", "billiards", "pool", "felt"],
				"desc": "A billiard table. One ball left on the felt: the eight."},
			{"id": "cue_rack", "name": "cue rack", "keys": ["cue", "cues", "rack"],
				"desc": "A rack of cues. One is snapped in half."},
			{"id": "dartboard", "name": "dartboard", "keys": ["dartboard", "darts", "dart"],
				"desc": "A dartboard, bristling with old darts.", "nick": "the Cyclops",
				"memory": "The dartboard... the Cyclops. You two never once hit its eye."},
		],
	},
	{
		"id": "music", "name": "Music Room", "rect": [12, 3, 4, 3], "phone": false,
		"features": ["clock", "rain"],
		"objects": [
			{"id": "gramophone", "name": "gramophone", "keys": ["gramophone", "phonograph", "record", "records"],
				"desc": "A gramophone with a cracked record on it.", "nick": "the Singing Box",
				"memory": "The gramophone... the Singing Box. It only ever played one waltz."},
			{"id": "harp", "name": "harp", "keys": ["harp", "strings"],
				"desc": "A tall harp with three strings missing."},
			{"id": "music_stand", "name": "music stand", "keys": ["sheet", "sheets", "score"],
				"desc": "A music stand. The sheet on it is blank."},
		],
	},
	{
		"id": "bathroom", "name": "Bathroom", "rect": [12, 6, 4, 3], "phone": true,
		"features": ["fan", "radiator"],
		"objects": [
			{"id": "bathtub", "name": "clawfoot bathtub", "keys": ["bathtub", "bath", "tub"],
				"desc": "A clawfoot bathtub with a grey ring around it."},
			{"id": "medicine_cabinet", "name": "medicine cabinet", "keys": ["medicine", "pills", "bottles"],
				"desc": "A medicine cabinet full of brown bottles."},
			{"id": "laundry_chute", "name": "laundry chute", "keys": ["chute", "laundry", "linen"],
				"desc": "The little door of a laundry chute."},
		],
	},
]
const EXTRA_DOORS := [["nursery", "billiard"], ["kitchen", "music"], ["pantry", "bathroom"], ["billiard", "music"], ["music", "bathroom"]]
const EXTRA_FLAVOR := {
	"billiard_table": "the billiard table's slate top slides aside over a stairwell",
	"cue_rack": "pull the broken cue and the rack swings open",
	"dartboard": "behind the Cyclops is a hole just big enough to crawl through",
	"gramophone": "the gramophone cabinet has no back — it opens into the wall",
	"harp": "the harp's pedestal hides a floor hatch",
	"music_stand": "the music stand's base is a lever for a floor panel",
	"bathtub": "under the bathtub, the floor drops into the old cistern",
	"medicine_cabinet": "the medicine cabinet is a door to a service shaft",
	"laundry_chute": "the laundry chute goes all the way down — and out",
}
const CS_EXTRA_ROOMS := {
	"billiard": ["Kulečníkový sál", "v kulečníkovém sále", "do kulečníkového sálu", ["kulecnik*", "billiard*"]],
	"music": ["Hudební salonek", "v hudebním salonku", "do hudebního salonku", ["hudeb*"]],
	"bathroom": ["Koupelna", "v koupelně", "do koupelny", ["koupel*"]],
}
const CS_EXTRA_OBJECTS := {
	"billiard_table": ["kulečníkový stůl", "Kulečníkový stůl. Na suknu zbyla jediná koule: osmička.", ["kulecnik*", "sukn*"]],
	"cue_rack": ["stojan s tágy", "Stojan s tágy. Jedno je zlomené vejpůl.", ["tag*", "tago"]],
	"dartboard": ["terč na šipky", "Terč, ze kterého trčí staré šipky.", ["terc*", "sipk*"], "Kyklop", "Terč… Kyklop. Ani jednou jste se mu netrefili do oka."],
	"gramophone": ["gramofon", "Gramofon s prasklou deskou.", ["gramofon*", "desk*"], "Zpívající skříňka", "Gramofon… Zpívající skříňka. Hrál pořád jen jeden valčík."],
	"harp": ["harfa", "Vysoká harfa, chybějí jí tři struny.", ["harf*", "strun*"]],
	"music_stand": ["notový stojan", "Notový stojan. List na něm je prázdný.", ["noty", "notov*", "partitur*"]],
	"bathtub": ["vana na nožičkách", "Vana na lvích nožičkách se šedým okrajem.", ["vana", "vane", "vanu", "vanou"]],
	"medicine_cabinet": ["lékárnička", "Lékárnička plná hnědých lahviček.", ["lekarn*", "prasky", "leky", "lahvic*"]],
	"laundry_chute": ["shoz na prádlo", "Dvířka shozu na prádlo.", ["shoz*", "prad*"]],
}
const CS_EXTRA_FLAVOR := {
	"billiard_table": "břidlicová deska kulečníku se odsune nad schodiště",
	"cue_rack": "zatáhni za zlomené tágo a stojan se otevře",
	"dartboard": "za Kyklopem je díra, kterou se dá prolézt",
	"gramophone": "skříňka gramofonu nemá zadní stěnu — vede do zdi",
	"harp": "podstavec harfy zakrývá poklop v podlaze",
	"music_stand": "noha notového stojanu je páka k panelu v podlaze",
	"bathtub": "pod vanou se podlaha propadá do staré cisterny",
	"medicine_cabinet": "lékárnička jsou dvířka do servisní šachty",
	"laundry_chute": "shoz na prádlo vede až úplně dolů — a ven",
}

## Czech data. Keys ending in * are stems (prefix match on diacritics-folded words).
const CS_ROOMS := {
	"library": ["Knihovna", "v knihovně", "do knihovny", ["knihovn*"]],
	"study": ["Pracovna", "v pracovně", "do pracovny", ["pracovn*", "kancelar*"]],
	"nursery": ["Dětský pokoj", "v dětském pokoji", "do dětského pokoje", ["detsk*", "pokojic*"]],
	"parlor": ["Salon", "v salonu", "do salonu", ["salon*", "obyvak*"]],
	"hall": ["Hala", "v hale", "do haly", ["hala", "hale", "halu", "halou", "predsin*", "vstup*"]],
	"kitchen": ["Kuchyně", "v kuchyni", "do kuchyně", ["kuchyn*"]],
	"conservatory": ["Zimní zahrada", "v zimní zahradě", "do zimní zahrady", ["zimn*", "zahrad*", "sklenik*"]],
	"dining": ["Jídelna", "v jídelně", "do jídelny", ["jideln*"]],
	"pantry": ["Spíž", "ve spíži", "do spíže", ["spiz*"]],
}

## object id -> [name, desc, keys, nick, memory]
const CS_OBJECTS := {
	"bookcase": ["vysoký regál s knihami", "Vysoký regál s knihami. Jeden svazek chybí a zbyla po něm tmavá mezera.", ["regal*", "svazk*", "knizk*"]],
	"globe": ["starý glóbus", "Zaprášený glóbus. Někdo na něj nakreslil malou lebku na místo Čech.", ["glob*"]],
	"armchair": ["kožené křeslo", "Popraskané kožené křeslo. Nějak pořád vypadá teple.", ["kresl*", "kozen*"]],
	"desk": ["těžký dubový stůl", "Těžký dubový psací stůl. Šuplíky jsou zamčené.", ["dubov*", "suplik*", "supl*"]],
	"horse_painting": ["obraz koně", "Obraz šedého koně.", ["obraz*", "malb*", "kun", "kone", "koni", "konem"], "Kapitán", "Šedý kůň ve zlaceném rámu… Kapitán. Každé ráno jste mu spolu salutovali."],
	"typewriter": ["psací stroj", "Černý psací stroj s rozepsaným dopisem.", ["stroj*", "psaci"]],
	"bear": ["plyšový medvěd", "Plyšový medvěd s jedním knoflíkovým okem.", ["medv*", "plys*", "hrack*"], "Pan Knoflík", "Jednooký plyšový medvěd… Pan Knoflík! Hlídal ti postel."],
	"rocking_horse": ["houpací kůň", "Dřevěný houpací kůň. Zavrže, jen když se na něj podíváš.", ["houpac*", "kun", "kone", "koni", "konem"]],
	"dollhouse": ["domeček pro panenky", "Domeček pro panenky — maličká kopie tohohle domu.", ["domec*", "panenk*"]],
	"piano": ["babiččin klavír", "Babiččin klavír se zavřeným víkem.", ["klavir*", "piano*", "kridl*"]],
	"fireplace": ["krb", "Studený krb plný šedého popela.", ["krb*", "komin*", "popel*"]],
	"mirror": ["vysoké zrcadlo", "Vysoké zrcadlo. Dlouho se do něj nedíváš.", ["zrcad*"]],
	"stag": ["jelení hlava", "Vycpaná jelení hlava se skleněnýma očima.", ["jelen*", "parohy", "paroh*", "trofej*"], "Starý Řehoř", "Jelení hlava… Starý Řehoř. Oba jste přísahali, že jednou mrkl."],
	"staircase": ["schodiště", "Široké schodiště. Patro je zatlučené prkny.", ["schod*", "zabradl*"]],
	"umbrella_stand": ["stojan na deštníky", "Stojan na deštníky ze sloní nohy. Hrůza.", ["destnik*", "stojan*", "hul", "hole"]],
	"stove": ["litinová kamna", "Velká litinová kamna. Prkna před nimi se viklají.", ["kamn*", "sporak*"]],
	"dumbwaiter": ["jídelní výtah", "Dvířka jídelního výtahu ve zdi.", ["vytah*", "sacht*", "dvirk*"], "Duchovka", "Jídelní výtah… Duchovka. Jednou jste v ní uvízli na celou hodinu."],
	"knife_block": ["stojan na nože", "Stojan na nože. Jedna škvíra je prázdná. Snažíš se na to nemyslet.", ["noz*", "nuz*"]],
	"birdcage": ["prázdná ptačí klec", "Prázdná mosazná klec.", ["klec*", "ptac*", "kanar*"], "Pípův palác", "Mosazná klec… Pípův palác. Píp byl kanárek. Pohřbili jste ho u růží."],
	"fern": ["uschlá kapradina", "Obrovská uschlá kapradina v prasklém květináči.", ["kaprad*", "kvetin*", "rostlin*"]],
	"wicker_chair": ["proutěné křeslo", "Proutěné křeslo se lehce houpe. Nefouká.", ["prouten*", "kresl*"]],
	"long_table": ["dlouhý stůl", "Dlouhý stůl prostřený pro dvanáct. Roky tu nikdo nejedl.", ["stol*", "stul", "ubrus*", "tabul*"]],
	"china_cabinet": ["vitrína s porcelánem", "Vitrína s porcelánem. Každý šálek je otlučený.", ["vitrin*", "porcelan*", "salk*", "salek", "talir*"]],
	"chandelier": ["lustr", "Křišťálový lustr, který se nepatrně houpe.", ["lustr*", "kristal*"]],
	"jam_shelf": ["police se zavařeninami", "Police se zavařeninami, popsané roztřesenou rukou: 1987, 1988, 1989…", ["zavaren*", "marmelad*", "sklenic*", "dzem*"]],
	"flour_sacks": ["pytle mouky", "Hromada pytlů s moukou. Něco malého si v nich udělalo hnízdo.", ["pytl*", "pytel", "mouk*"]],
	"meat_hook": ["hák na maso", "Rezavý hák na maso na kolejnici. Prázdný. Naštěstí.", ["hak", "haku", "hakem", "haky", "hak*"]],
}

const CS_EXIT_FLAVOR := {
	"bookcase": "zatáhni za mezeru po chybějícím svazku a regál se otevře na stará služebnická schodiště",
	"globe": "podstavec glóbu je poklop do průlezu, který vede pod zahradou",
	"armchair": "pod křeslem je padací dveře do starého uhelného tunelu",
	"desk": "pod deskou stolu je falešná zadní stěna do chodby",
	"horse_painting": "za Kapitánem jsou malá dvířka do chodby ve zdi",
	"typewriter": "stolek s psacím strojem zakrývá poklop v podlaze",
	"bear": "Pan Knoflík sedí na uvolněném panelu, pod kterým je skluz",
	"rocking_horse": "pod houpacím koněm jsou padací dveře",
	"dollhouse": "panel ve zdi za domečkem jsou tajné dveře",
	"piano": "pod klavírem jdou zvednout prkna do tunelu",
	"fireplace": "zadní deska krbu se odsune do komínové chodby",
	"mirror": "zrcadlo jsou dveře — zatlač na levý okraj",
	"stag": "zatáhni Starého Řehoře za levý paroh a otevře se panel",
	"staircase": "komora pod schody má falešnou podlahu",
	"umbrella_stand": "za stojanem na deštníky se otvírá nízký panel",
	"stove": "uvolněná prkna před kamny vedou do sklepa",
	"dumbwaiter": "šachta jídelního výtahu vede dolů do uhelného tunelu",
	"knife_block": "kachlíky za stojanem na nože jsou poklop",
	"birdcage": "háček klece je páka ke skleněným dveřím v zahradní zdi",
	"fern": "květináč kapradiny zakrývá kanál, kterým se dá prolézt",
	"wicker_chair": "pod proutěným křeslem se otevírá mříž",
	"long_table": "pod dlouhým stolem jsou padací dveře",
	"china_cabinet": "vitrína se otevírá na pantech",
	"chandelier": "řetěz lustru je táhlo, které otevře panel ve zdi",
	"jam_shelf": "police se zavařeninami se vyklopí do staré ledárny",
	"flour_sacks": "pod pytli s moukou je poklop",
	"meat_hook": "stáhni hák dolů a zadní stěna se otevře",
}


func room_name(id: String) -> String:
	return cs_room(id)[0] if Loc.lang == "cs" else rooms[id].name


## "in the Library" / "v knihovně"
func room_in(id: String) -> String:
	return cs_room(id)[1] if Loc.lang == "cs" else "in the " + rooms[id].name


## "into the Library" / "do knihovny"
func room_to(id: String) -> String:
	return cs_room(id)[2] if Loc.lang == "cs" else "the " + rooms[id].name


func obj_name(oid: String) -> String:
	return cs_obj(oid)[0] if Loc.lang == "cs" else object_def(oid).name


func obj_desc(oid: String) -> String:
	return cs_obj(oid)[1] if Loc.lang == "cs" else object_def(oid).desc


func obj_nick(oid: String) -> String:
	var o := object_def(oid)
	if not o.has("nick"):
		return ""
	return cs_obj(oid)[3] if Loc.lang == "cs" else o.nick


func obj_memory(oid: String) -> String:
	var o := object_def(oid)
	if not o.has("memory"):
		return ""
	return cs_obj(oid)[4] if Loc.lang == "cs" else o.memory


func exit_flavor(oid: String) -> String:
	if Loc.lang == "cs":
		return CS_EXIT_FLAVOR.get(oid, CS_EXTRA_FLAVOR.get(oid, ""))
	return EXIT_FLAVOR.get(oid, EXTRA_FLAVOR.get(oid, ""))

var rooms := {}          # id -> room dict
var room_ids: Array[String] = []
var adj := {}            # id -> {dir: other_id}
var doors: Array = []    # [[a, b], ...] for this instance
var object_room := {}    # object id -> room id
var _dist := {}          # id -> {id: int}


func _init(large := false) -> void:
	var defs: Array = ROOMS + (EXTRA_ROOMS if large else [])
	for r in defs:
		rooms[r.id] = r.duplicate(true)
		room_ids.append(r.id)
		for o in r.objects:
			object_room[o.id] = r.id
	_build(DOORS + (EXTRA_DOORS if large else []))


## Plan size in units (12 x 9, or 16 x 9 for the large house).
func size_units() -> Vector2:
	var s := Vector2.ZERO
	for id in room_ids:
		s = s.max(rect(id).end)
	return s


static func cs_room(id: String) -> Array:
	return CS_ROOMS[id] if CS_ROOMS.has(id) else CS_EXTRA_ROOMS[id]


static func cs_obj(oid: String) -> Array:
	return CS_OBJECTS[oid] if CS_OBJECTS.has(oid) else CS_EXTRA_OBJECTS[oid]


func _build(door_list: Array) -> void:
	doors = door_list.duplicate(true)
	adj.clear()
	_dist.clear()
	for id in room_ids:
		adj[id] = {}
	for d in doors:
		var a: String = d[0]
		var b: String = d[1]
		var dir := direction_between(a, b)
		adj[a][dir] = b
		adj[b][opposite(dir)] = a
	for a in room_ids:
		_dist[a] = _bfs(a)


## "Rearranged house" variant: random doors (a spanning tree plus a couple of
## loops), random phones and random room sounds. Room names, positions and
## objects stay, so memories and the plan still make sense.
func rearrange() -> void:
	var pairs := []
	for a in room_ids:
		for b in room_ids:
			if a < b and rect(a).grow(0.01).intersects(rect(b)) and _shared_edge(a, b):
				pairs.append([a, b])
	pairs.shuffle()
	# Kruskal with union-find for a random spanning tree.
	var parent := {}
	for id in room_ids:
		parent[id] = id
	var find := func(x): return x
	find = func(x):
		while parent[x] != x:
			x = parent[x]
		return x
	var chosen := []
	var spare := []
	for pr in pairs:
		var ra = find.call(pr[0])
		var rb = find.call(pr[1])
		if ra != rb:
			parent[ra] = rb
			chosen.append(pr)
		else:
			spare.append(pr)
	for i in mini(randi_range(2, 3), spare.size()):
		chosen.append(spare[i])
	_build(chosen)
	# Phones: two thirds of the rooms.
	var ids := room_ids.duplicate()
	ids.shuffle()
	for i in ids.size():
		rooms[ids[i]].phone = i < ids.size() * 2 / 3
	# Sounds: random, every room has at least one.
	var odds := {"clock": 0.45, "fan": 0.35, "rain": 0.5, "radiator": 0.4}
	for id in room_ids:
		var f := []
		for k in FEATURES:
			if randf() < odds[k]:
				f.append(k)
		if f.is_empty():
			f.append(FEATURES.pick_random())
		rooms[id].features = f


func _shared_edge(a: String, b: String) -> bool:
	var ra := rect(a)
	var rb := rect(b)
	var ox := minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)
	var oy := minf(ra.end.y, rb.end.y) - maxf(ra.position.y, rb.position.y)
	return (ox > 0.5 and absf(oy) < 0.01) or (oy > 0.5 and absf(ox) < 0.01)


static func opposite(dir: String) -> String:
	return {"north": "south", "south": "north", "east": "west", "west": "east"}[dir]


func center(id: String) -> Vector2:
	var r: Array = rooms[id].rect
	return Vector2(r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)


func rect(id: String) -> Rect2:
	var r: Array = rooms[id].rect
	return Rect2(r[0], r[1], r[2], r[3])


func direction_between(a: String, b: String) -> String:
	var v := center(b) - center(a)
	if absf(v.x) >= absf(v.y):
		return "east" if v.x > 0 else "west"
	return "south" if v.y > 0 else "north"


func neighbors(id: String) -> Array:
	return adj[id].values()


func door_to(a: String, b: String) -> String:
	for dir in adj[a]:
		if adj[a][dir] == b:
			return dir
	return ""


func step(id: String, dir: String) -> String:
	return adj[id].get(dir, "")


func distance(a: String, b: String) -> int:
	return _dist[a].get(b, 99)


func path(a: String, b: String) -> Array:
	## Rooms after `a` up to and including `b`.
	if a == b:
		return []
	var prev := {a: ""}
	var q := [a]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == b:
			break
		for n in neighbors(cur):
			if not prev.has(n):
				prev[n] = cur
				q.append(n)
	var out := []
	var c := b
	while c != a and c != "":
		out.push_front(c)
		c = prev.get(c, "")
	return out


func rooms_within(id: String, d: int) -> Array:
	var out := []
	for r in room_ids:
		if distance(id, r) <= d:
			out.append(r)
	return out


func rooms_at(id: String, d: int) -> Array:
	var out := []
	for r in room_ids:
		if distance(id, r) == d:
			out.append(r)
	return out


func phone_rooms() -> Array:
	var out := []
	for r in room_ids:
		if rooms[r].phone:
			out.append(r)
	return out


func has_feature(id: String, f: String) -> bool:
	return f in rooms[id].features


func object_def(obj_id: String) -> Dictionary:
	var rid: String = object_room.get(obj_id, "")
	if rid == "":
		return {}
	for o in rooms[rid].objects:
		if o.id == obj_id:
			return o
	return {}


func _bfs(a: String) -> Dictionary:
	var d := {a: 0}
	var q := [a]
	while not q.is_empty():
		var cur: String = q.pop_front()
		for n in neighbors(cur):
			if not d.has(n):
				d[n] = d[cur] + 1
				q.append(n)
	return d
