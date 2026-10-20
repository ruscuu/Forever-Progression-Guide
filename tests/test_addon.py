"""Pruebas del addon en un Lua 5.1 real (el de WoW) con la API simulada.

Requiere `pip install lupa`. Ejecutar desde la raíz del repositorio:
    python -m unittest discover -s tests
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "ForeverProgressionGuide"
sys.path.insert(0, str(ROOT / "pipeline"))

try:
    from lupa import lua51
except ImportError:  # pragma: no cover
    lua51 = None


def toc_files(toc):
    lines = (ADDON / toc).read_text(encoding="utf-8").splitlines()
    return [l.strip().replace("\\", "/") for l in lines if l.strip() and not l.startswith("#")]


@unittest.skipIf(lua51 is None, "lupa no está instalado")
class AddonTestCase(unittest.TestCase):
    def setUp(self):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / "tests" / "wowmock.lua").read_text(encoding="utf-8"))
        self.lua.execute("NS = {}\nfunction load_addon_file(src, name) assert(loadstring(src, '@' .. name))('ForeverProgressionGuide', NS) end")
        self.mock = self.lua.globals().WOWMOCK
        self.load()

    def load(self):
        loader = self.lua.globals().load_addon_file
        for name in toc_files("ForeverProgressionGuide.toc"):
            loader((ADDON / name).read_text(encoding="utf-8"), name)
        self.ns = self.lua.globals().NS
        self.fire("ADDON_LOADED", "ForeverProgressionGuide")
        self.fire("PLAYER_LOGIN")

    def fire(self, event, *args):
        self.mock.Fire(event, *args)

    def run_lua(self, code):
        return self.lua.execute(code)

    def errors(self):
        return list(self.ns.errors.values())

    def tearDown(self):
        self.assertEqual(self.errors(), [], "el addon registró errores")


class LoadingTest(AddonTestCase):
    def test_tocs_list_every_lua_file_once(self):
        listed = toc_files("ForeverProgressionGuide.toc")
        self.assertEqual(listed, toc_files("ForeverProgressionGuide_Camelot.toc"))
        on_disk = sorted(str(p.relative_to(ADDON)).replace("\\", "/") for p in ADDON.rglob("*.lua"))
        self.assertEqual(sorted(listed), on_disk)
        self.assertEqual(len(listed), len(set(listed)))

    def test_icon_texture_exists_and_header_uses_it(self):
        line = next(l for l in (ADDON / "ForeverProgressionGuide.toc").read_text(encoding="utf-8").splitlines() if l.startswith("## IconTexture:"))
        path = line.split(":", 1)[1].strip().replace("\\", "/")
        self.assertTrue(path.startswith("Interface/AddOns/ForeverProgressionGuide/"), path)
        self.assertTrue((ADDON / (path.split("ForeverProgressionGuide/", 1)[1] + ".tga")).exists())
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.assertEqual(self.lua.eval("ForeverProgressionGuideFrame.logo.__texture"), line.split(":", 1)[1].strip())

    def test_saved_variables_get_defaults(self):
        db = self.lua.globals().ForeverProgressionGuideDB
        self.assertEqual(db.settings.language, "auto")
        self.assertEqual(self.ns.lang, "es")

    def test_data_is_loaded(self):
        deadmines = self.ns.Data.Dungeons["the-deadmines"]
        self.assertEqual((deadmines.id, deadmines.instanceID), ("the-deadmines", 36))
        self.assertEqual(deadmines.provenance.levels, "datamined")
        self.assertGreater(self.lua.eval("(function() local n = 0 for _ in pairs(NS.Data.Items) do n = n + 1 end return n end)()"), 1000)
        self.assertEqual(self.ns.Data.Quests[166].dungeon, "the-deadmines")


class LocalizationTest(AddonTestCase):
    def test_both_languages_have_the_same_keys(self):
        en = set(self.ns.Locales.en.keys())
        es = set(self.ns.Locales.es.keys())
        self.assertEqual(sorted(en - es), [], "faltan en español")
        self.assertEqual(sorted(es - en), [], "faltan en inglés")

    def test_every_literal_key_used_in_code_exists(self):
        en = set(self.ns.Locales.en.keys())
        used = set()
        for path in ADDON.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            used |= set(re.findall(r'\bL\.([A-Z][A-Z0-9_]+)', text))
            used |= set(re.findall(r'\bL\["([A-Z][A-Z0-9_]+)"\]', text))
            used |= set(re.findall(r'\bL\("([A-Z][A-Z0-9_]+)"', text))
        self.assertEqual(sorted(used - en), [])

    def test_dynamic_keys_exist(self):
        en = set(self.ns.Locales.en.keys())
        expected = set()
        for prefix, values in {
            "CATEGORY_": ["recommended", "reward", "optional", "too_early", "unverified", "unavailable"],
            "STATUS_": ["verified_ingame", "datamined", "classic_inherited", "announced", "unknown"],
            "REASON_LEVELS_": ["datamined", "classic_inherited", "announced", "unknown"],
            "CONFIDENCE_": ["high", "medium", "low", "none"],
            "FACTION_": ["both", "alliance", "horde"],
            "TAB_": ["progress", "dungeons", "gear", "quests", "professions", "search", "options"],
            "KIND_": ["dungeon", "wing", "boss", "quest", "item"],
            "FIT_": ["best", "usable", "no"],
            "BTN_": ["info", "quests", "loot", "map"],
            "BOSSES_FROM_": ["journal", "data"],
            "FIELD_": ["exists", "levels", "bosses"],
        }.items():
            expected |= {prefix + v.upper() for v in values}
        slots = self.lua.eval("(function() local t = {} for _, s in ipairs(NS.Gear.SLOTS) do t[#t + 1] = s.key end return t end)()")
        expected |= {"SLOT_" + s for s in slots.values()}
        self.assertEqual(sorted(expected - en), [])

    def test_language_switch(self):
        SlashCmdList = self.lua.globals().SlashCmdList
        SlashCmdList.FOREVERPROGRESSIONGUIDE("en")
        self.assertEqual(self.ns.L.TAB_DUNGEONS, "Dungeons")
        self.assertEqual(self.lua.eval("NS.Dungeons.Name(NS.Data.Dungeons['the-deadmines'])"), "The Deadmines")
        SlashCmdList.FOREVERPROGRESSIONGUIDE("es")
        self.assertEqual(self.ns.L.TAB_DUNGEONS, "Mazmorras")
        self.assertEqual(self.lua.eval("NS.Dungeons.Name(NS.Data.Dungeons['the-deadmines'])"), "Las Minas de la Muerte")


class DungeonEngineTest(AddonTestCase):
    def evaluate(self, dungeon_id, level, faction="alliance"):
        return self.lua.eval(f"NS.Dungeons.Evaluate(NS.Data.Dungeons['{dungeon_id}'], {{ level = {level}, faction = '{faction}' }})")

    def reason_keys(self, ev):
        return [r[1] for r in ev.reasons.values()]

    def test_in_range_is_recommended_with_low_confidence(self):
        ev = self.evaluate("the-deadmines", 20)
        self.assertEqual(ev.category, "recommended")
        self.assertEqual(ev.confidence, "medium")
        self.assertIn("levels_datamined", self.reason_keys(ev))

    def test_too_early_and_overleveled(self):
        self.assertEqual(self.evaluate("blackrock-depths", 20).category, "too_early")
        self.assertEqual(self.evaluate("the-deadmines", 40).category, "optional")
        self.assertEqual(self.evaluate("blackrock-depths", 50).category, "recommended", "margen de 2 niveles por debajo del mínimo")

    def test_other_faction_dungeon_is_optional(self):
        ev = self.evaluate("ragefire-chasm", 15, "alliance")
        self.assertEqual(ev.category, "optional")
        self.assertIn("other_faction", self.reason_keys(ev))
        self.assertEqual(self.evaluate("ragefire-chasm", 15, "horde").category, "recommended")

    def test_announced_dungeon_is_unavailable(self):
        ev = self.evaluate("the-drowned-city", 37)
        self.assertEqual(ev.category, "unavailable")
        self.assertEqual(self.reason_keys(ev)[0], "unavailable")

    def test_bosses_come_from_journal_when_available(self):
        origin = self.lua.eval("select(2, NS.Dungeons.Bosses(NS.Data.Dungeons['the-deadmines']))")
        self.assertEqual(origin, "journal")
        origin = self.lua.eval("select(2, NS.Dungeons.Bosses(NS.Data.Dungeons['blackrock-depths']))")
        self.assertEqual(origin, "data")

    def test_undocumented_journal_instance_is_discovered(self):
        self.run_lua("""
          table.insert(WOWMOCK.journal.instances, { journalID = 900, name = "Ruinas de Lordaeron", uiMapID = 2000, instanceID = 9999, isRaid = false })
          NS.Journal.Reset()
        """)
        d = self.lua.eval("NS.Dungeons.Get(9999)")
        self.assertEqual(d.status, "datamined")
        self.assertEqual(self.lua.eval("NS.Dungeons.Evaluate(NS.Dungeons.Get(9999), { level = 20, faction = 'alliance' }).category"), "unverified")
        ids = self.lua.eval("(function() local t = {} for _, o in ipairs(NS.Objectives.Generate(NS.Compat.Player())) do t[#t+1] = o.id end return t end)()")
        self.assertIn("explore:9999", list(ids.values()))


class ObjectivesTest(AddonTestCase):
    def ids(self):
        return list(self.lua.eval("(function() local t = {} for _, o in ipairs(NS.Objectives.Generate(NS.Compat.Player())) do t[#t+1] = o.id end return t end)()").values())

    def test_dungeon_and_gear_objectives(self):
        ids = self.ids()
        self.assertTrue(any(i.startswith("dungeon:") for i in ids), ids)
        self.assertTrue(any(i.startswith("gear:") for i in ids), "sin equipo, hay ranuras vacías")

    def test_done_hides_and_postponed_goes_last_until_level_up(self):
        first = self.ids()[0]
        self.lua.globals().NS.Objectives.SetState(first, "postponed")
        ids = self.ids()
        self.assertNotEqual(ids[0], first)
        self.assertTrue(first not in ids or ids[-1] == first, "lo pospuesto va al final (o queda fuera del límite)")
        self.fire("PLAYER_LEVEL_UP", 21)
        self.assertEqual(self.ids()[0], first)
        self.lua.globals().NS.Objectives.SetState(first, "done")
        self.assertNotIn(first, self.ids())

    def test_stale_data_warning(self):
        self.run_lua("NS.Data.Meta.latestBuildSeen = '1.60.1.100'")
        self.assertIn("data:1.60.1.12345", self.ids())
        self.run_lua("NS.Data.Meta.latestBuildSeen = '1.60.1.12345'")
        self.assertNotIn("data:1.60.1.12345", self.ids())


class CollectorTest(AddonTestCase):
    def enter_deadmines(self):
        self.fire("ZONE_CHANGED")  # en exteriores: anota la posición
        self.run_lua("""
          WOWMOCK.inInstance, WOWMOCK.instanceType = true, "party"
          WOWMOCK.instance = { name = "Las Minas de la Muerte", type = "party", maxPlayers = 5, instanceID = 36 }
        """)
        self.fire("PLAYER_ENTERING_WORLD")
        self.fire("ENCOUNTER_END", 1234, "Edwin VanCleef", 1, 5, 1)
        self.fire("ENCOUNTER_END", 1235, "Wipe", 1, 5, 0)

    def test_instance_observation(self):
        self.enter_deadmines()
        rec = self.lua.globals().ForeverProgressionGuideDB.contributions.instances[36]
        self.assertEqual(rec.name, "Las Minas de la Muerte")
        self.assertEqual(rec.locale, "esES")
        self.assertTrue(rec.uiMapIDs[291])
        self.assertEqual(rec.levels[20], 1)
        self.assertEqual(rec.entrance.mapID, 52)
        self.assertEqual(rec.entrance.x, 0.42)
        self.assertEqual(rec.encounters[1234].kills, 1)
        self.assertIsNone(rec.encounters[1235], "un intento fallido no cuenta")

    def test_quest_events_both_signatures(self):
        self.fire("QUEST_ACCEPTED", 155)
        self.fire("QUEST_ACCEPTED", 3, 156)
        self.fire("QUEST_TURNED_IN", 155, 1200, 0)
        quests = self.lua.globals().ForeverProgressionGuideDB.contributions.quests
        self.assertEqual(quests[155].xp, 1200)
        self.assertEqual(quests[155].level, 18)
        self.assertEqual(quests[156].accepted, 1)

    def test_collect_off(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("collect off")
        self.fire("QUEST_ACCEPTED", 155)
        self.assertIsNone(self.lua.globals().ForeverProgressionGuideDB.contributions.quests[155])

    def test_round_trip_through_pipeline(self):
        """Lo observado en el juego vuelve como dato verificado al generar."""
        import build_data
        import import_contributions
        from luatable import parse_assignments

        self.enter_deadmines()
        text = self.mock.SavedVariablesText("ForeverProgressionGuideDB")
        db = parse_assignments(text)["ForeverProgressionGuideDB"]
        contrib = import_contributions.normalize(db["contributions"])
        records = build_data.load_seed(build_data.fc_dungeons(build_data.load_fc(), build_data.load_zone_translations()))
        notes = []
        build_data.apply_contributions(records, [("test.json", contrib)], notes)
        dm = records["the-deadmines"]
        self.assertEqual(dm["provenance"]["exists"]["status"], "verified_ingame")
        self.assertEqual(dm["observed"]["uiMapIDs"], [291])
        self.assertEqual(dm["observed"]["entrance"]["mapID"], 52)
        self.assertEqual(dm["name"]["es"], "Las Minas de la Muerte")
        self.assertEqual(dm["provenance"]["levels"]["status"], "datamined", "entrar no verifica el rango de niveles")


class ClassFilterTest(AddonTestCase):
    def current(self):
        return self.lua.eval("NS.ClassFilter.Current()")

    def test_defaults_to_player_class_and_current_spec(self):
        c = self.current()
        self.assertEqual((c.classID, c.specID, c.className, c.specName, c.isPlayer), (1, 71, "Guerrero", "Armas", True))
        self.assertEqual(self.lua.eval("NS.ClassFilter.Label()"), "Guerrero · Armas")

    def test_change_class_resets_spec_and_is_saved(self):
        F = self.lua.globals().NS.ClassFilter
        F.SetSpec(73)
        self.assertEqual(self.current().role, "TANK")
        F.SetClass(8)
        c = self.current()
        self.assertEqual((c.classID, c.specID, c.isPlayer), (8, 0, False))
        F.SetSpec(64)
        self.assertEqual(self.lua.eval("ForeverProgressionGuideCharDB.filter.specID"), 64)
        F.SetClass(1)
        self.assertTrue(self.current().isPlayer, "volver a la clase propia restaura el personaje")
        self.assertEqual(self.current().specID, 71)

    def test_loot_uses_selected_class_and_spec(self):
        self.lua.globals().NS.ClassFilter.SetClass(8)
        self.lua.globals().NS.ClassFilter.SetSpec(63)
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.run_lua("NS.UI.Select('dungeons', { id = 'the-deadmines' }); local b = NS.UI.tabs.dungeons.panel.modes.loot; b:GetScript('OnClick')(b)")
        self.assertTrue(self.lua.eval("NS.UI.tabs.dungeons.panel.listMessage:GetText()").startswith("Botín para: Mago · Fuego"))
        self.run_lua("WOWMOCK.calls = {}; local f = EJ_SetLootFilter; EJ_SetLootFilter = function(c, s) table.insert(WOWMOCK.calls, c .. ':' .. s) f(c, s) end")
        self.lua.eval("NS.Journal.Loot(63, NS.ClassFilter.Current().classID, NS.ClassFilter.Current().specID)")
        self.assertEqual(list(self.mock.calls.values()), ["8:63"])

    def test_header_selectors(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.assertEqual(self.lua.eval("ForeverProgressionGuideFrame.classSelector.button:GetText()"), "Guerrero")
        self.assertEqual(self.lua.eval("ForeverProgressionGuideFrame.specSelector.button:GetText()"), "Armas")
        # Abrir el desplegable de clase y elegir «Mago».
        self.run_lua("ForeverProgressionGuideFrame.classSelector:Open()")
        labels = list(self.lua.eval("""(function()
          local t = {}
          for _, item in ipairs(ForeverProgressionGuideFrame.classSelector.items) do t[#t + 1] = item.label:GetText() end
          return t
        end)()""").values())
        self.assertEqual(labels[0], "|cffffd100Mi personaje|r", "la opción activa se resalta")
        self.assertIn("Mago", labels)
        self.run_lua("""
          for _, item in ipairs(ForeverProgressionGuideFrame.classSelector.items) do
            if item.label:GetText() == 'Mago' then item.__scripts.OnClick(item) end
          end""")
        self.assertEqual(self.lua.eval("ForeverProgressionGuideFrame.classSelector.button:GetText()"), "Mago")
        self.assertEqual(self.lua.eval("ForeverProgressionGuideFrame.specSelector.button:GetText()"), "Todas las especializaciones")
        # Una clase sin especializaciones oculta el segundo selector.
        self.lua.globals().NS.ClassFilter.SetClass(5)
        self.assertFalse(self.lua.eval("ForeverProgressionGuideFrame.specSelector.button:IsShown()"))
        self.lua.globals().NS.ClassFilter.Reset()
        self.assertTrue(self.lua.eval("ForeverProgressionGuideFrame.specSelector.button:IsShown()"))

    def test_without_spec_api_falls_back_to_class(self):
        self.run_lua("GetNumSpecializationsForClassID = nil; GetSpecialization = nil")
        c = self.current()
        self.assertEqual((c.classID, c.specID, c.specName), (1, 0, None))
        self.assertEqual(self.lua.eval("NS.ClassFilter.Label()"), "Guerrero")


class FirstLevelsTest(AddonTestCase):
    """Personaje de nivel 3 en un cliente con el diario vacío, como en Forever."""

    def setUp(self):
        super().setUp()
        self.run_lua("""
          WOWMOCK.player.level = 3; WOWMOCK.player.faction = 'Horde'
          WOWMOCK.journal.instances = {}
          NS.Journal.Reset()
        """)

    def objectives(self):
        return self.lua.eval("(function() local t = {} for _, o in ipairs(NS.Objectives.Generate(NS.Compat.Player())) do t[#t+1] = o end return t end)()")

    def test_next_dungeon_is_suggested(self):
        objs = list(self.objectives().values())
        nxt = [o for o in objs if o.kind == "next"]
        self.assertEqual(len(nxt), 1)
        self.assertEqual(nxt[0].id, "next:ragefire-chasm", "Sima Ígnea, la primera para la Horda")
        self.assertEqual(nxt[0].title, "Próxima mazmorra: Sima Ígnea")
        self.assertEqual(nxt[0].reasons[1], "desde el nivel 11 (te faltan 8 niveles)")

    def test_next_dungeon_respects_faction(self):
        self.run_lua("WOWMOCK.player.faction = 'Alliance'")
        ids = [o.id for o in self.objectives().values()]
        self.assertIn("next:hall-of-thanes", ids, "para la Alianza, Hall of Thanes en Forjaz (nueva en Forever)")
        self.assertNotIn("next:ragefire-chasm", ids)

    def test_hidden_objectives_are_counted_and_recoverable(self):
        self.run_lua("NS.Objectives.SetState('next:ragefire-chasm', 'dismissed')")
        hidden = self.lua.eval("select(2, NS.Objectives.Generate(NS.Compat.Player()))")
        self.assertGreaterEqual(hidden, 1)
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.assertTrue(self.lua.eval("NS.UI.tabs.progress.panel.showHidden:IsShown()"))
        self.run_lua("local b = NS.UI.tabs.progress.panel.showHidden; b:GetScript('OnClick')(b)")
        self.assertEqual(self.lua.eval("select(2, NS.Objectives.Generate(NS.Compat.Player()))"), 0)

    def test_map_found_by_name_without_journal(self):
        mapID, origin = self.lua.eval("NS.Journal.MapFor(NS.Data.Dungeons['the-deadmines'])")
        self.assertEqual((mapID, origin), (291, "name"), "el mapa del cliente se llama «Las Minas de la Muerte»")
        self.assertIsNone(self.lua.eval("NS.Journal.MapFor(NS.Data.Dungeons['blackrock-depths'])"))

    def test_diag_command(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("diag")
        out = "\n".join(self.mock.printed.values())
        self.assertIn("Diario de mazmorras: funciones sí · instancias 0", out)
        self.assertIn("Las Minas de la Muerte → 291 (name)", out)
        self.assertIn("Especializaciones: API sí · 3 para tu clase", out)
        self.assertIn("icono del minimapa: visible", out)

    def test_professions_empty_state(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.run_lua("NS.UI.Select('professions')")
        self.assertIn("Todavía no tienes profesiones", self.lua.eval("NS.UI.tabs.professions.panel.empty:GetText()"))


class ItemsAndQuestsTest(AddonTestCase):
    def fit(self, item, class_file, level=20):
        return self.lua.eval(f"NS.Items.Fit({item}, '{class_file}', {level})")

    def test_item_fit_rules(self):
        cloth_int = "{ armor = 'cloth', stats = { 'int', 'spi' } }"
        self.assertEqual(self.fit(cloth_int, "PRIEST"), "best")
        self.assertEqual(self.fit("{ armor = 'plate', stats = { 'str' } }", "PRIEST"), "no")
        self.assertEqual(self.fit("{ weapon = 'Sword', slot = 'Two-Hand', stats = { 'agi' } }", "ROGUE"), "no")
        self.assertEqual(self.fit("{ weapon = 'Sword', slot = 'One-Hand', stats = { 'agi' } }", "ROGUE"), "best")
        self.assertEqual(self.fit("{ armor = 'mail', stats = { 'str' } }", "WARRIOR", 20), "best")
        self.assertEqual(self.fit("{ armor = 'leather', stats = { 'str' } }", "WARRIOR", 20), "usable")
        self.assertEqual(self.fit("{ armor = 'plate', stats = { 'str' } }", "WARRIOR", 40), "best")
        self.assertEqual(self.fit("{ armor = 'cloth', stats = { 'str' } }", "MAGE"), "usable", "estadísticas que no le sirven")

    def test_upgrade_against_equipped_item(self):
        self.run_lua("WOWMOCK.gear[1] = 'x ilvl20'")
        self.assertEqual(self.lua.eval("NS.Items.Upgrade({ slot = 'Head', ilvl = 25 })"), 5)
        self.assertEqual(self.lua.eval("NS.Items.Upgrade({ slot = 'Finger', ilvl = 12 })"), 12, "sin anillos puestos")
        self.assertIsNone(self.lua.eval("NS.Items.Upgrade({ slot = 'Bag', ilvl = 5 })"))

    def test_dungeon_loot_for_a_priest_hides_unusable(self):
        loot = self.lua.eval("NS.Items.DungeonLoot(NS.Data.Dungeons['the-deadmines'], 'PRIEST', 20, true)")
        fits = [e.fit for e in loot.values()]
        self.assertTrue(fits)
        self.assertNotIn("no", fits)
        everything = self.lua.eval("#NS.Items.DungeonLoot(NS.Data.Dungeons['the-deadmines'], 'PRIEST', 20, false)")
        self.assertGreater(everything, len(fits))
        self.assertTrue(self.lua.eval("NS.Items.Icon(872)").startswith("Interface\\Icons\\"))

    def test_quests_by_faction_prerequisites_and_done(self):
        alliance = "{ level = 22, faction = 'alliance', class = 'WARRIOR' }"
        horde = "{ level = 22, faction = 'horde', class = 'WARRIOR' }"
        self.assertTrue(self.lua.eval(f"NS.Quests.Available(NS.Data.Quests[166], {alliance})"))
        self.assertFalse(self.lua.eval(f"NS.Quests.Available(NS.Data.Quests[166], {horde})"), "misión de la Alianza")
        self.assertEqual(list(self.lua.eval("NS.Quests.MissingPrereqs(NS.Data.Quests[166])").values()), [155])
        self.run_lua("WOWMOCK.completedQuests[155] = true")
        self.assertEqual(len(self.lua.eval("NS.Quests.MissingPrereqs(NS.Data.Quests[166])")), 0)
        before = self.lua.eval(f"#NS.Quests.ForDungeon(NS.Data.Dungeons['the-deadmines'], {alliance})")
        self.run_lua("WOWMOCK.completedQuests[166] = true")
        after = self.lua.eval(f"#NS.Quests.ForDungeon(NS.Data.Dungeons['the-deadmines'], {alliance})")
        self.assertEqual(after, before - 1, "las hechas no cuentan")
        lines = "\n".join(self.lua.eval("NS.Quests.TooltipLines(NS.Data.Quests[166])").values())
        self.assertIn("Gryan Stoutmantle", lines)

    def test_class_quest_and_zone_objectives(self):
        self.run_lua("""
          WOWMOCK.player.level = 10; WOWMOCK.player.faction = 'Horde'
          NS.Data.ClassQuests['test'] = { id = 'test', class = 'WARRIOR', level = 10, name = 'Prueba', reward = 'Actitud defensiva', essential = true, faction = 'both' }
        """)
        objs = list(self.lua.eval("NS.Objectives.Generate(NS.Compat.Player())")[0].values())
        kinds = {o.kind: o for o in objs}
        self.assertEqual(kinds["class"].title, "Misión de clase: Actitud defensiva")
        self.assertIn("zone", kinds)
        self.assertTrue(kinds["zone"].title.startswith("Haz misiones en "))

    def test_quests_tab_lists_available_quests(self):
        self.run_lua("WOWMOCK.player.level = 22")
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.run_lua("NS.UI.Select('quests')")
        intro = self.lua.eval("NS.UI.tabs.quests.panel.intro:GetText()")
        self.assertRegex(intro, r"^\d+ misiones de mazmorra")
        self.run_lua("local b = NS.UI.tabs.quests.panel.log; b:GetScript('OnClick')(b)")


class RealDataSmokeTest(AddonTestCase):
    """Todas las mazmorras, en todos los modos, con varias clases y niveles."""

    def test_every_dungeon_in_every_mode(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        count = self.lua.eval("""(function()
          local n = 0
          for _, setup in ipairs({ { 'WARRIOR', 1, 20, 'Alliance' }, { 'PRIEST', 5, 45, 'Horde' }, { 'MAGE', 8, 60, 'Alliance' } }) do
            WOWMOCK.player.class, WOWMOCK.player.classID, WOWMOCK.player.level, WOWMOCK.player.faction = setup[1], setup[2], setup[3], setup[4]
            for id in pairs(NS.Data.Dungeons) do
              NS.UI.Select('dungeons', { id = id })
              local panel = NS.UI.tabs.dungeons.panel
              for _, mode in ipairs({ 'quests', 'loot', 'map', 'info' }) do
                local b = panel.modes[mode]
                b:GetScript('OnClick')(b)
              end
              n = n + 1
            end
            for _, tab in ipairs({ 'progress', 'quests', 'gear', 'search' }) do NS.UI.Select(tab) end
          end
          return n
        end)()""")
        self.assertEqual(count, 3 * 42)

    def test_search_many_queries(self):
        for query in ("de", "the", "sword", "staff", "defias", "a", "ñ", "ragnaros"):
            self.lua.globals().NS.Search(query)

    def test_tooltips_for_every_quest(self):
        self.lua.execute("for _, q in pairs(NS.Data.Quests) do NS.Quests.TooltipLines(q) end")


class MinimapAndOptionsTest(AddonTestCase):
    def button(self):
        return self.lua.globals().ForeverProgressionGuideMinimapButton

    def click(self, frame_expr, mouse="LeftButton"):
        self.run_lua(f"local b = {frame_expr}; b.__scripts.OnClick(b, '{mouse}')")

    def test_minimap_button_toggles_guide_and_opens_options(self):
        self.assertTrue(self.lua.eval("ForeverProgressionGuideMinimapButton:IsShown()"))
        self.click("ForeverProgressionGuideMinimapButton")
        self.assertTrue(self.lua.eval("NS.UI.IsShown()"))
        self.click("ForeverProgressionGuideMinimapButton")
        self.assertFalse(self.lua.eval("NS.UI.IsShown()"))
        self.click("ForeverProgressionGuideMinimapButton", "RightButton")
        self.assertTrue(self.lua.eval("NS.UI.IsShown('options')"))

    def test_minimap_button_is_placed_on_the_edge_and_drag_saves_angle(self):
        point = self.lua.eval("ForeverProgressionGuideMinimapButton.__point")
        x, y = point[4], point[5]
        self.assertAlmostEqual((x * x + y * y) ** 0.5, 80, places=3, msg="radio del minimapa + 10")
        # El cursor justo encima del centro del minimapa (100, 100) → 90 grados.
        self.run_lua("""WOWMOCK.cursor = { 100, 200 }
          local b = ForeverProgressionGuideMinimapButton
          b.__scripts.OnDragStart(b); b.__scripts.OnUpdate(b); b.__scripts.OnDragStop(b)""")
        self.assertAlmostEqual(self.lua.eval("ForeverProgressionGuideDB.settings.minimap.angle"), 90)
        self.assertIsNone(self.lua.eval("ForeverProgressionGuideMinimapButton.__scripts.OnUpdate"))

    def test_hide_minimap_from_options_and_slash(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("opciones")
        self.assertEqual(self.mock.settings.opened, 42, "abre la ventana de opciones del juego")
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("minimapa")
        self.assertFalse(self.lua.eval("ForeverProgressionGuideMinimapButton:IsShown()"))
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("minimap")
        self.assertTrue(self.lua.eval("ForeverProgressionGuideMinimapButton:IsShown()"))

    def test_options_tab_controls(self):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        self.run_lua("NS.UI.Select('options')")
        self.run_lua("NS.Objectives.SetState('dungeon:36', 'dismissed')")
        self.run_lua("""
          local o = NS.UI.tabs.options.panel.controls
          local function click(b, checked)
            if checked ~= nil then b:SetChecked(checked) end
            b:GetScript('OnClick')(b)
          end
          click(o.minimap, false)
          click(o.collect, false)
          click(o.resetObjectives)
          click(o.languages.en)
        """)
        db = self.lua.globals().ForeverProgressionGuideDB
        self.assertTrue(db.settings.minimap.hide)
        self.assertFalse(self.lua.eval("ForeverProgressionGuideMinimapButton:IsShown()"))
        self.assertFalse(db.settings.collect)
        self.assertIsNone(self.lua.eval("ForeverProgressionGuideCharDB.objectives['dungeon:36']"))
        self.assertEqual(db.settings.language, "en")
        self.assertEqual(self.lua.eval("NS.UI.tabs.options.panel.controls.minimap.label:GetText()"), "Show minimap icon")

    def test_game_options_panel_is_registered_and_renders(self):
        self.assertEqual(self.mock.settings.registered.name, "Forever Progression Guide")
        self.run_lua("local f = WOWMOCK.settings.category.frame; f:GetScript('OnShow')(f)")

    def test_without_settings_api_options_open_in_the_guide(self):
        self.lua.execute("Settings = nil")
        self.lua.globals().NS.UI.OpenGameOptions = self.lua.eval("function() return false end")
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("options")
        self.assertTrue(self.lua.eval("NS.UI.IsShown('options')"))

    def test_addon_compartment_right_click_opens_options(self):
        self.lua.globals().ForeverProgressionGuide_OnAddonCompartmentClick("ForeverProgressionGuide", "RightButton")
        self.assertTrue(self.lua.eval("NS.UI.IsShown('options')"))


class UITest(AddonTestCase):
    def open(self, tab=None, arg="nil"):
        self.lua.globals().SlashCmdList.FOREVERPROGRESSIONGUIDE("")
        if tab:
            self.run_lua(f"NS.UI.Select('{tab}', {arg})")

    def test_every_tab_renders(self):
        self.run_lua("WOWMOCK.gear[1] = '|Hitem:1|h[Casco]|h ilvl20'; WOWMOCK.gear[5] = '|Hitem:2|h[Peto]|h ilvl8'")
        self.open()
        for tab in ("progress", "dungeons", "gear", "quests", "professions", "search"):
            self.run_lua(f"NS.UI.Select('{tab}')")
        self.assertTrue(self.lua.eval("ForeverProgressionGuideFrame:IsShown()"))

    def test_dungeon_detail_modes(self):
        self.open("dungeons", "{ id = 'the-deadmines' }")
        for button in ("modes.map", "modes.loot", "modes.quests", "modes.info", "route"):
            self.run_lua(f"local b = NS.UI.tabs.dungeons.panel.{button}; b:GetScript('OnClick')(b)")
        self.assertEqual(self.mock.waypoint.mapID, 52)
        self.assertEqual(self.lua.eval("NS.UI.tabs.dungeons.panel.name:GetText()"), "Las Minas de la Muerte")

    def test_dungeon_map_draws_client_tiles_and_boss_pins(self):
        tiles = self.lua.eval("""(function()
          local view = NS.UI.MapView(UIParent)
          view:ShowDungeon(NS.Data.Dungeons['the-deadmines'])
          local shown, pins = 0, 0
          for _, t in ipairs(view.tiles) do if t:IsShown() then shown = shown + 1 end end
          for _, p in ipairs(view.pins) do if p:IsShown() then pins = pins + 1 end end
          return shown, pins, view.pins[1].bossName
        end)()""")
        self.assertEqual(tiles, (12, 1, "Rhahk'Zor"))

    def test_map_without_id_explains_how_to_get_it(self):
        text = self.lua.eval("""(function()
          local view = NS.UI.MapView(UIParent)
          view:ShowDungeon(NS.Data.Dungeons['blackrock-depths'])
          return view.message:GetText()
        end)()""")
        self.assertIn("Entra una vez", text)

    def test_waypoint_to_journal_entrance(self):
        entrance, origin = self.lua.eval("NS.Journal.Entrance(NS.Data.Dungeons['the-deadmines'])")
        self.assertEqual((entrance.uiMapID, entrance.zone, origin), (52, "Páramos de Poniente", "journal"))
        self.assertTrue(self.lua.eval("NS.Journal.SetWaypoint(52, 0.42, 0.72)"))
        self.assertTrue(self.mock.superTracked)

    def test_class_loot(self):
        loot = self.lua.eval("NS.Journal.Loot(63, 1)")
        self.assertEqual(loot[1].itemID, 5191)

    def test_search_in_both_languages(self):
        labels = lambda q: [r.label for r in self.lua.globals().NS.Search(q).values()]
        self.assertIn("Las Minas de la Muerte", labels("deadmines"))
        self.assertTrue(any("Rockslicer" in l for l in labels("rockslicer")), "objetos del botín")
        self.assertTrue(any("Defias Brotherhood" in l for l in labels("defias brotherhood")), "misiones")
        self.assertIn("Las Minas de la Muerte", labels("minas"))
        self.assertTrue(any("VanCleef" in l for l in labels("vancleef")))
        self.assertTrue(any("Catedral" in l for l in labels("cathedral")))


if __name__ == "__main__":
    unittest.main()
