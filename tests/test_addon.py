"""Pruebas del addon en un Lua 5.1 real (el de WoW) con la API simulada.

Requiere `pip install lupa`. Ejecutar desde la raíz del repositorio:
    python -m unittest discover -s tests
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "WoWForeverGuide"
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
        self.lua.execute("NS = {}\nfunction load_addon_file(src, name) assert(loadstring(src, '@' .. name))('WoWForeverGuide', NS) end")
        self.mock = self.lua.globals().WOWMOCK
        self.load()

    def load(self):
        loader = self.lua.globals().load_addon_file
        for name in toc_files("WoWForeverGuide.toc"):
            loader((ADDON / name).read_text(encoding="utf-8"), name)
        self.ns = self.lua.globals().NS
        self.fire("ADDON_LOADED", "WoWForeverGuide")
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
        listed = toc_files("WoWForeverGuide.toc")
        self.assertEqual(listed, toc_files("WoWForeverGuide_Camelot.toc"))
        on_disk = sorted(str(p.relative_to(ADDON)).replace("\\", "/") for p in ADDON.rglob("*.lua"))
        self.assertEqual(sorted(listed), on_disk)
        self.assertEqual(len(listed), len(set(listed)))

    def test_saved_variables_get_defaults(self):
        db = self.lua.globals().WoWForeverGuideDB
        self.assertEqual(db.settings.language, "auto")
        self.assertEqual(self.ns.lang, "es")

    def test_data_is_loaded(self):
        deadmines = self.ns.Data.Dungeons[36]
        self.assertEqual(deadmines.id, "deadmines")
        self.assertEqual(deadmines.provenance.levels, "classic_inherited")


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
            "CATEGORY_": ["recommended", "reward", "optional", "too_early", "unverified"],
            "STATUS_": ["verified_ingame", "datamined", "classic_inherited", "announced", "unknown"],
            "REASON_LEVELS_": ["datamined", "classic_inherited", "announced", "unknown"],
            "CONFIDENCE_": ["high", "medium", "low", "none"],
            "FACTION_": ["both", "alliance", "horde"],
            "TAB_": ["progress", "dungeons", "gear", "quests", "professions", "search"],
            "KIND_": ["dungeon", "wing", "boss"],
            "BOSSES_FROM_": ["journal", "data"],
            "FIELD_": ["exists", "levels", "bosses"],
        }.items():
            expected |= {prefix + v.upper() for v in values}
        slots = self.lua.eval("(function() local t = {} for _, s in ipairs(NS.Gear.SLOTS) do t[#t + 1] = s.key end return t end)()")
        expected |= {"SLOT_" + s for s in slots.values()}
        self.assertEqual(sorted(expected - en), [])

    def test_language_switch(self):
        SlashCmdList = self.lua.globals().SlashCmdList
        SlashCmdList.WOWFOREVERGUIDE("en")
        self.assertEqual(self.ns.L.TAB_DUNGEONS, "Dungeons")
        self.assertEqual(self.lua.eval("NS.Dungeons.Name(NS.Data.Dungeons[36])"), "The Deadmines")
        SlashCmdList.WOWFOREVERGUIDE("es")
        self.assertEqual(self.ns.L.TAB_DUNGEONS, "Mazmorras")
        self.assertEqual(self.lua.eval("NS.Dungeons.Name(NS.Data.Dungeons[36])"), "Las Minas de la Muerte")


class DungeonEngineTest(AddonTestCase):
    def evaluate(self, instance_id, level, faction="alliance"):
        return self.lua.eval(f"NS.Dungeons.Evaluate(NS.Data.Dungeons[{instance_id}], {{ level = {level}, faction = '{faction}' }})")

    def reason_keys(self, ev):
        return [r[1] for r in ev.reasons.values()]

    def test_in_range_is_recommended_with_low_confidence(self):
        ev = self.evaluate(36, 20)
        self.assertEqual(ev.category, "recommended")
        self.assertEqual(ev.confidence, "low")
        self.assertIn("levels_classic_inherited", self.reason_keys(ev))

    def test_too_early_and_overleveled(self):
        self.assertEqual(self.evaluate(230, 20).category, "too_early")
        self.assertEqual(self.evaluate(36, 40).category, "optional")
        self.assertEqual(self.evaluate(230, 50).category, "recommended", "margen de 2 niveles por debajo del mínimo")

    def test_other_faction_dungeon_is_optional(self):
        ev = self.evaluate(389, 15, "alliance")
        self.assertEqual(ev.category, "optional")
        self.assertIn("other_faction", self.reason_keys(ev))
        self.assertEqual(self.evaluate(389, 15, "horde").category, "recommended")

    def test_best_wing_is_chosen(self):
        ev = self.evaluate(189, 41)
        self.assertEqual(ev.category, "recommended")
        self.assertEqual(ev.wing.id, "cathedral")
        self.assertEqual(self.evaluate(189, 30).wing.id, "graveyard")

    def test_bosses_come_from_journal_when_available(self):
        origin = self.lua.eval("select(2, NS.Dungeons.Bosses(NS.Data.Dungeons[36]))")
        self.assertEqual(origin, "journal")
        origin = self.lua.eval("select(2, NS.Dungeons.Bosses(NS.Data.Dungeons[230]))")
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
        self.assertEqual(self.ids()[-1], first)
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
        rec = self.lua.globals().WoWForeverGuideDB.contributions.instances[36]
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
        quests = self.lua.globals().WoWForeverGuideDB.contributions.quests
        self.assertEqual(quests[155].xp, 1200)
        self.assertEqual(quests[155].level, 18)
        self.assertEqual(quests[156].accepted, 1)

    def test_collect_off(self):
        self.lua.globals().SlashCmdList.WOWFOREVERGUIDE("collect off")
        self.fire("QUEST_ACCEPTED", 155)
        self.assertIsNone(self.lua.globals().WoWForeverGuideDB.contributions.quests[155])

    def test_round_trip_through_pipeline(self):
        """Lo observado en el juego vuelve como dato verificado al generar."""
        import build_data
        import import_contributions
        from luatable import parse_assignments

        self.enter_deadmines()
        text = self.mock.SavedVariablesText("WoWForeverGuideDB")
        db = parse_assignments(text)["WoWForeverGuideDB"]
        contrib = import_contributions.normalize(db["contributions"])
        records = build_data.load_seed()
        notes = []
        build_data.apply_contributions(records, [("test.json", contrib)], notes)
        dm = records["deadmines"]
        self.assertEqual(dm["provenance"]["exists"]["status"], "verified_ingame")
        self.assertEqual(dm["observed"]["uiMapIDs"], [291])
        self.assertEqual(dm["observed"]["entrance"]["mapID"], 52)
        self.assertEqual(dm["name"]["es"], "Las Minas de la Muerte")
        self.assertEqual(dm["provenance"]["levels"]["status"], "classic_inherited", "entrar no verifica el rango de niveles")


class UITest(AddonTestCase):
    def open(self, tab=None, arg="nil"):
        self.lua.globals().SlashCmdList.WOWFOREVERGUIDE("")
        if tab:
            self.run_lua(f"NS.UI.Select('{tab}', {arg})")

    def test_every_tab_renders(self):
        self.run_lua("WOWMOCK.gear[1] = '|Hitem:1|h[Casco]|h ilvl20'; WOWMOCK.gear[5] = '|Hitem:2|h[Peto]|h ilvl8'")
        self.open()
        for tab in ("progress", "dungeons", "gear", "quests", "professions", "search"):
            self.run_lua(f"NS.UI.Select('{tab}')")
        self.assertTrue(self.lua.eval("WoWForeverGuideFrame:IsShown()"))

    def test_dungeon_detail_modes(self):
        self.open("dungeons", "{ instanceID = 36 }")
        for button in ("modeMap", "modeLoot", "modeInfo", "route"):
            self.run_lua(f"local b = NS.UI.tabs.dungeons.panel.{button}; b.__scripts.OnClick(b)")
        self.assertEqual(self.mock.waypoint.mapID, 52)
        self.assertEqual(self.lua.eval("NS.UI.tabs.dungeons.panel.name:GetText()"), "Las Minas de la Muerte")

    def test_dungeon_map_draws_client_tiles_and_boss_pins(self):
        tiles = self.lua.eval("""(function()
          local view = NS.UI.MapView(UIParent)
          view:ShowDungeon(NS.Data.Dungeons[36])
          local shown, pins = 0, 0
          for _, t in ipairs(view.tiles) do if t:IsShown() then shown = shown + 1 end end
          for _, p in ipairs(view.pins) do if p:IsShown() then pins = pins + 1 end end
          return shown, pins, view.pins[1].bossName
        end)()""")
        self.assertEqual(tiles, (12, 1, "Rhahk'Zor"))

    def test_map_without_id_explains_how_to_get_it(self):
        text = self.lua.eval("""(function()
          local view = NS.UI.MapView(UIParent)
          view:ShowDungeon(NS.Data.Dungeons[230])
          return view.message:GetText()
        end)()""")
        self.assertIn("Entra una vez", text)

    def test_waypoint_to_journal_entrance(self):
        entrance, origin = self.lua.eval("NS.Journal.Entrance(NS.Data.Dungeons[36])")
        self.assertEqual((entrance.uiMapID, entrance.zone, origin), (52, "Páramos de Poniente", "journal"))
        self.assertTrue(self.lua.eval("NS.Journal.SetWaypoint(52, 0.42, 0.72)"))
        self.assertTrue(self.mock.superTracked)

    def test_class_loot(self):
        loot = self.lua.eval("NS.Journal.Loot(63, 1)")
        self.assertEqual(loot[1].itemID, 5191)

    def test_search_in_both_languages(self):
        labels = lambda q: [r.label for r in self.lua.globals().NS.Search(q).values()]
        self.assertIn("Las Minas de la Muerte", labels("deadmines"))
        self.assertIn("Las Minas de la Muerte", labels("minas"))
        self.assertTrue(any("VanCleef" in l for l in labels("vancleef")))
        self.assertTrue(any("Catedral" in l for l in labels("cathedral")))


if __name__ == "__main__":
    unittest.main()
