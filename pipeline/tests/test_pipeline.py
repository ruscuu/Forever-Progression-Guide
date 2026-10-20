import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import build_data  # noqa: E402
from import_contributions import normalize  # noqa: E402
from luatable import LuaParseError, parse_assignments, to_lua  # noqa: E402

SAVED_VARIABLES = r'''
ForeverProgressionGuideDB = {
	["schema"] = 1,
	["settings"] = {
		["language"] = "auto", -- comentario
		["collect"] = true,
	},
	["contributions"] = {
		["builds"] = { ["1.60.1.12345"] = true },
		["instances"] = {
			[36] = {
				["name"] = "Las Minas de la Muerte",
				["locale"] = "esES",
				["type"] = "party",
				["maxPlayers"] = 5,
				["uiMapIDs"] = { [291] = true, [292] = true },
				["levels"] = { [18] = 1, [21] = 2 },
				["encounters"] = { [1234] = { ["name"] = "Edwin VanCleef", ["kills"] = 1 } },
				["entrance"] = { ["mapID"] = 52, ["x"] = 0.42, ["y"] = 0.71 },
			},
			[9999] = {
				["name"] = "Ruins of Lordaeron",
				["locale"] = "enUS",
				["type"] = "party",
				["maxPlayers"] = 5,
				["levels"] = { [25] = 1 },
			},
			[1] = { ["type"] = "none" },
		},
		["quests"] = { [155] = { ["level"] = 18, ["xp"] = 1200 } },
	},
}
ForeverProgressionGuideCharDB = nil
'''


class LuaTableTest(unittest.TestCase):
    def test_parses_saved_variables(self):
        data = parse_assignments(SAVED_VARIABLES)
        db = data["ForeverProgressionGuideDB"]
        self.assertIsNone(data["ForeverProgressionGuideCharDB"])
        self.assertTrue(db["settings"]["collect"])
        self.assertEqual(db["contributions"]["instances"][36]["entrance"]["x"], 0.42)

    def test_sequences_become_lists_and_escapes_decode(self):
        data = parse_assignments('X = { "a", "b\\"c", "Ma\\195\\177ana", -2.5e1, 0x10 }')
        self.assertEqual(data["X"], ["a", 'b"c', "Mañana", -25.0, 16])

    def test_rejects_code(self):
        with self.assertRaises(LuaParseError):
            parse_assignments("X = os.execute('rm')")

    def test_to_lua_is_deterministic_and_round_trips(self):
        value = {"b": [1, 2], "a": {"en": "It's \"x\"", "es": "Sí"}, 36: {"nested": {"deep": [{"k": True}]}}}
        text = to_lua(value)
        self.assertEqual(text, to_lua(copy.deepcopy(value)))
        self.assertEqual(parse_assignments("X = " + text)["X"], value)


def all_records():
    """Mazmorras como las genera el pipeline: Forever Companion más la semilla."""
    records = build_data.fc_dungeons(build_data.load_fc(), build_data.load_zone_translations())
    return build_data.load_seed(records)


class ContributionsTest(unittest.TestCase):
    def merged(self):
        db = parse_assignments(SAVED_VARIABLES)["ForeverProgressionGuideDB"]
        contrib = normalize(db["contributions"])
        records = all_records()
        notes = []
        quests, builds = build_data.apply_contributions(records, [("a.json", contrib)], notes)
        return records, quests, builds, notes

    def test_known_dungeon_gets_observations(self):
        records, quests, builds, _ = self.merged()
        dm = records["the-deadmines"]
        self.assertEqual(dm["observed"]["uiMapIDs"], [291, 292])
        self.assertEqual(dm["observed"]["levelsSeen"], {"min": 18, "max": 21})
        self.assertEqual(dm["observed"]["encounters"], [{"id": 1234, "name": "Edwin VanCleef"}])
        self.assertEqual(quests[155]["xp"], 1200)
        self.assertEqual(builds, ["1.60.1.12345"])

    def test_new_forever_dungeon_learns_its_instance_id_by_name(self):
        records, _, _, notes = self.merged()
        ruins = records["ruins-of-lordaeron"]
        self.assertEqual(ruins["instanceID"], 9999)
        self.assertEqual(ruins["provenance"]["instanceID"]["status"], "verified_ingame")
        self.assertTrue(any("9999" in n for n in notes))
        self.assertNotIn("instance-9999", records)
        self.assertNotIn("instance-1", records, "las zonas exteriores se ignoran")

    def test_truly_unknown_instance_becomes_new_record(self):
        records, notes = all_records(), []
        build_data.apply_contributions(records, [("x.json", {"instances": {"777": {
            "name": "Mazmorra Secreta", "locale": "esES", "type": "party", "maxPlayers": 5}}})], notes)
        new = records["instance-777"]
        self.assertEqual((new["name"], new["type"]), ({"es": "Mazmorra Secreta"}, "dungeon"))
        self.assertNotIn("levels", new, "no se inventa un rango de niveles")

    def test_shared_instance_keeps_wing_names(self):
        records, notes = all_records(), []
        build_data.apply_contributions(records, [("x.json", {"instances": {"189": {
            "name": "Monasterio Escarlata", "locale": "esES", "type": "party"}}})], notes)
        self.assertEqual(records["sm-library"]["name"]["es"], "Monasterio Escarlata: Biblioteca")
        self.assertEqual(records["sm-library"]["provenance"]["exists"]["status"], "verified_ingame")

    def test_result_validates_and_renders(self):
        records, quests, builds, _ = self.merged()
        build_data.validate(records)
        files = build_data.render_outputs(records, {}, quests, builds, None)
        meta_lua = files[build_data.ADDON_DATA_DIR / "Meta.lua"]
        self.assertIn('latestBuildSeen = "1.60.1.12345"', meta_lua)
        self.assertIn("verified_ingame = 2", meta_lua, "las Minas y las Ruinas de Lordaeron, vistas en el juego")


class FieldPriorityTest(unittest.TestCase):
    def test_lower_confidence_never_overwrites(self):
        record = {"provenance": {"levels": {"status": "verified_ingame", "source": "x"}}, "levels": {"min": 10, "max": 15}}
        self.assertFalse(build_data.apply_field(record, "levels.min", 99, "classic_inherited", "seed"))
        self.assertEqual(record["levels"]["min"], 10)
        self.assertTrue(build_data.apply_field(record, "levels.min", 12, "verified_ingame", "y"))
        self.assertEqual(record["levels"]["min"], 12)

    def test_builds_sort_numerically(self):
        self.assertLess(build_data.build_key("1.60.1.9999"), build_data.build_key("1.60.1.10000"))


class ValidationTest(unittest.TestCase):
    def test_detects_broken_records(self):
        records = all_records()
        bad = copy.deepcopy(records["the-deadmines"])
        bad["id"] = "copy"
        bad["levels"] = {"min": 30, "max": 20}
        bad["faction"] = "pirates"
        bad["quests"] = [999999999]
        records["copy"] = bad
        quests = build_data.fc_quests(build_data.load_fc())
        with self.assertRaises(build_data.ValidationError) as ctx:
            build_data.validate(records, quests)
        message = str(ctx.exception)
        self.assertIn("rango de niveles", message)
        self.assertIn("faction", message)
        self.assertIn("misiones inexistentes", message)

    def test_all_sources_are_valid(self):
        fc = build_data.load_fc()
        build_data.validate(all_records(), build_data.fc_quests(fc), build_data.fc_items(fc), [])


class ForeverCompanionTest(unittest.TestCase):
    def setUp(self):
        self.fc = build_data.load_fc()
        self.assertIsNotNone(self.fc, "falta data-sources/imported/forevercompanion.json")

    def test_dungeons_get_spanish_names_and_instance_ids_from_seed(self):
        records = all_records()
        dm = records["the-deadmines"]
        self.assertEqual(dm["name"], {"en": "The Deadmines", "es": "Las Minas de la Muerte"})
        self.assertEqual(dm["instanceID"], 36)
        self.assertEqual(dm["zone"]["es"], "Páramos de Poniente")
        self.assertEqual(dm["provenance"]["levels"]["status"], "datamined")
        self.assertTrue(dm["loot"] and dm["quests"])
        self.assertIn("molten-core", records, "las bandas salen de la semilla")
        self.assertNotIn("instanceID", records["hall-of-thanes"], "las nuevas no tienen ID hasta verlas en el juego")

    def test_announced_dungeons_are_unavailable(self):
        records = all_records()
        self.assertFalse(records["the-drowned-city"]["available"])
        self.assertEqual(records["the-drowned-city"]["provenance"]["levels"]["status"], "announced")
        self.assertTrue(records["the-deadmines"]["available"])

    def test_quest_status_and_prerequisites(self):
        quests = build_data.fc_quests(self.fc)
        q = quests[166]
        self.assertEqual(q["dungeon"], "the-deadmines")
        self.assertEqual(q["prereqs"], [[155]])
        statuses = {x["status"] for x in quests.values()}
        self.assertTrue(statuses <= set(build_data.STATUS_RANK))

    def test_items_are_compact(self):
        items = build_data.fc_items(self.fc)
        self.assertGreater(len(items), 1000)
        item = next(iter(items.values()))
        self.assertTrue({"id", "name", "status"} <= set(item))
        self.assertNotIn(None, item.values())


class ChangeReportTest(unittest.TestCase):
    def test_reports_changes_and_removals(self):
        old = {"a": {"levels": {"min": 1, "max": 5}}, "gone": {}}
        new = {"a": {"levels": {"min": 2, "max": 5}}, "fresh": {"name": {"en": "Fresh"}}}
        report, removals = build_data.change_report(old, new, ["nota"])
        self.assertTrue(removals)
        self.assertIn("`a.levels.min`: `1` → `2`", report)
        self.assertIn("**Nueva:** `fresh`", report)
        self.assertIn("**Eliminada (revisar):** `gone`", report)


class ImportTest(unittest.TestCase):
    def run_import(self, allowed):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            raw = tmp / "raw" / "src" / "20261020-000000"
            raw.mkdir(parents=True)
            (raw / "dungeons.json").write_text(json.dumps({"data": [
                {"mapId": 36, "minLevel": 15, "maxLevel": 21},
                {"mapId": 777, "minLevel": 1, "maxLevel": 5},
            ]}))
            (tmp / "sources.json").write_text(json.dumps({"sources": [{
                "id": "src", "name": "Fuente", "redistribution_allowed": allowed,
                "imports": [{"endpoint": "dungeons", "status": "datamined",
                             "fields": {"instanceID": "mapId", "levels.min": "minLevel", "levels.max": "maxLevel"}}],
            }]}))
            old = build_data.RAW_DIR, build_data.SOURCES_FILE
            build_data.RAW_DIR, build_data.SOURCES_FILE = tmp / "raw", tmp / "sources.json"
            try:
                records, notes = all_records(), []
                build_data.apply_imports(records, notes)
            finally:
                build_data.RAW_DIR, build_data.SOURCES_FILE = old
        return records, notes

    def test_authorized_source_overrides_classic_levels(self):
        records, notes = self.run_import(True)
        dm = records["the-deadmines"]
        self.assertEqual(dm["levels"], {"min": 15, "max": 21})
        self.assertEqual(dm["provenance"]["levels.min"]["status"], "datamined")
        self.assertEqual(build_data.collapse_provenance(dm["provenance"])["levels"], "datamined")
        self.assertIn("1 de 2", notes[0])

    def test_partial_update_keeps_weakest_status(self):
        record = {"levels": {"min": 1, "max": 5}, "provenance": {"levels": {"status": "classic_inherited", "source": "seed"}}}
        build_data.apply_field(record, "levels.min", 3, "verified_ingame", "x")
        self.assertEqual(build_data.collapse_provenance(record["provenance"]), {"levels": "classic_inherited"})
        build_data.apply_field(record, "levels.max", 6, "verified_ingame", "x")
        self.assertEqual(build_data.collapse_provenance(record["provenance"]), {"levels": "verified_ingame"})

    def test_unauthorized_source_is_skipped(self):
        records, notes = self.run_import(False)
        self.assertEqual(records["the-deadmines"]["levels"], {"min": 17, "max": 26})
        self.assertIn("redistribution_allowed", notes[0])


class RepositoryTest(unittest.TestCase):
    def test_committed_data_is_up_to_date(self):
        files, _, _ = build_data.build()
        stale = [str(p) for p, text in files.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        self.assertEqual(stale, [], "ejecuta python pipeline/build_data.py")


if __name__ == "__main__":
    unittest.main()
