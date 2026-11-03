import Foundation
import SwiftData
import Testing
@testable import NutriClone

// Las filas de ejemplo son datos de AESAN/BEDCA Base de Datos Española de Composición
// de Alimentos v1.0 (2010), tal y como aparecen en bedca_foods.csv del dataset de Zenodo.
private enum Fixture {
    static let header = "f_id,f_ori_name,f_eng_name,sci_name,langual,foodexcode,mainlevelcode,codlevel1,namelevel1,codsublevel,codlevel2,namelevel2,f_des_esp,f_des_ing,photo,edible_portion,f_origen,ALC,ALC_unit,ENERC,ENERC_unit,FAT,FAT_unit,PROT,PROT_unit,WATER,WATER_unit,CHO,CHO_unit,FIBT,FIBT_unit,STARCH,STARCH_unit,SUCS,SUCS_unit,SUGAR,SUGAR_unit,CHORL,CHORL_unit,F12:0,F12:0_unit,F14:0,F14:0_unit,F16:0,F16:0_unit,F18:0,F18:0_unit,F18:1CN9,F18:1CN9_unit,F18:2,F18:2_unit,F18:3,F18:3_unit,F20:4N6,F20:4N6_unit,F20:5,F20:5_unit,F22:6N3,F22:6N3_unit,FAMS,FAMS_unit,FAPU,FAPU_unit,FASAT,FASAT_unit,FATRS,FATRS_unit,BIOT,BIOT_unit,FOL,FOL_unit,NIAEQ,NIAEQ_unit,PANTAC,PANTAC_unit,RIBF,RIBF_unit,THIA,THIA_unit,VITA,VITA_unit,VITB12,VITB12_unit,VITB6,VITB6_unit,VITC,VITC_unit,VITD,VITD_unit,VITE,VITE_unit,CA,CA_unit,CU,CU_unit,FE,FE_unit,ID,ID_unit,K,K_unit,MG,MG_unit,NA,NA_unit,P,P_unit,SE,SE_unit,ZN,ZN_unit"

    static let bacon = #"680,"Bacón, ahumado, a la parrilla","Bacon, smoked, grilled",,A0279 A0459 A0633 A0666 A0714 A0726 A0799 B1136 C0269 E0150 F0014 G0006 H0172 H0173 H0253 J0106 K0003 M0001 N0001 P0024,,,,,,,,,,,1.000000,BEDCA,0,g,1215.5,kJ,22.1,g,23.4,g,50.5,g,0,g,0,g,0,g,,,0,g,80,mg,,,,,,,,,,,,,,,,,,,,,9.3,g,2.9,g,8.3,g,,,5,ug,2,ug,7,mg,1.22,mg,0.16,mg,0.9,mg,0,ug,1,ug,0.46,mg,,mg,0.6,ug,0.07,mg,7,mg,0.06,mg,0.7,mg,7,ug,330,mg,21,mg,1760,mg,190,mg,12,ug,2.2,mg"#

    static let coffee = #"681,"Café, con leche","Coffee infusion, with milk",,A0268 A0465 A0639 A0663 A0710 A0845 B1305 C0155 E0123 F0014 G0012 H0148 H0184 J0003 K0003 M0001 N0001 P0024 R0212 R0497 Z0109,,,,,,,,,,,1.000000,BEDCA,0,g,158.069,kJ,2.36538,g,1.7,g,94,g,2.45,g,0,g,0.15,g,,,2.3,g,8,mg,,,,,,,,,,,,,,,,,,,,,0.6235,g,0.0656,g,1.2032,g,,,,,1.66,ug,0.7,mg,,,0.08,mg,0.02,mg,15.8333,ug,0.1,ug,0.01,mg,0.5,mg,0.01,ug,0.04,mg,55,mg,,,0.05,mg,17.4,ug,90,mg,8,mg,23,mg,42,mg,2.8,ug,0.18,mg"#

    /// Con BOM y CRLF, como el fichero real.
    static var csv: String { "\u{FEFF}" + [header, bacon, coffee].joined(separator: "\r\n") + "\r\n" }
}

struct CSVParserTests {
    @Test func quotedFieldsAndEscapedQuotes() {
        let rows = CSVParser.parse("a,\"b, c\",\"d \"\"e\"\"\"\n1,,3")
        #expect(rows == [["a", "b, c", "d \"e\""], ["1", "", "3"]])
    }

    @Test func crlfBomAndTrailingNewline() {
        let rows = CSVParser.parse("\u{FEFF}x,y\r\n1,2\r\n")
        #expect(rows == [["x", "y"], ["1", "2"]])
    }

    @Test func newlineInsideQuotes() {
        let rows = CSVParser.parse("\"línea 1\nlínea 2\",z")
        #expect(rows == [["línea 1\nlínea 2", "z"]])
    }

    @Test func trailingEmptyFieldIsKept() {
        #expect(CSVParser.parse("a,b,\n") == [["a", "b", ""]])
    }

    @Test func fixtureRowsHaveHeaderWidth() {
        let rows = CSVParser.parse(Fixture.csv)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.count == rows[0].count })
        #expect(rows[0].count == 111)
    }
}

struct BedcaImporterTests {
    @Test func parsesRowsAndConvertsKilojoules() throws {
        let report = try BedcaImporter.parse(csv: Fixture.csv)
        #expect(report.foods.count == 2)
        #expect(report.skipped == 0)

        let bacon = try #require(report.foods.first { $0.id == 680 })
        #expect(bacon.name == "Bacón, ahumado, a la parrilla")
        #expect(abs(bacon.kcal - 1215.5 / 4.184) < 0.01)
        #expect(bacon.fat == 22.1)
        #expect(bacon.protein == 23.4)
        #expect(bacon.carbs == 0)
        #expect(bacon.sodiumMg == 1760)
        #expect(bacon.cholesterolMg == 80)
        #expect(bacon.saturatedFat == 8.3)
        // "VITC" viene vacío con unidad "mg": dato ausente, no cero.
        #expect(bacon.vitaminCMg == nil)

        let coffee = try #require(report.foods.first { $0.id == 681 })
        #expect(abs(coffee.kcal - 37.78) < 0.05)
        #expect(coffee.sugar == 2.3)
        #expect(coffee.calciumMg == 55)
    }

    @Test func missingRequiredColumnThrows() {
        #expect(throws: BedcaImporter.ImportError.missingColumn("ENERC")) {
            try BedcaImporter.parse(csv: "f_id,f_ori_name\n1,Agua\n")
        }
    }

    @Test func rowsWithoutEnergyAreSkipped() throws {
        let csv = "f_id,f_ori_name,ENERC,ENERC_unit\n1,Agua,,\n2,Leche,250,kJ\n"
        let report = try BedcaImporter.parse(csv: csv)
        #expect(report.foods.map(\.id) == [2])
        #expect(report.skipped == 1)
    }

    @Test func unitConversion() {
        #expect(BedcaImporter.convert(100, from: "kcal", to: .kcal) == 100)
        #expect(abs((BedcaImporter.convert(418.4, from: "kJ", to: .kcal) ?? 0) - 100) < 0.0001)
        #expect(BedcaImporter.convert(1500, from: "mg", to: .g) == 1.5)
        #expect(BedcaImporter.convert(2, from: "g", to: .mg) == 2000)
        #expect(BedcaImporter.convert(250, from: "ug", to: .mg) == 0.25)
        #expect(BedcaImporter.convert(1, from: "oz", to: .g) == nil)
        #expect(BedcaImporter.number("0,7") == 0.7)
    }

    @Test func duplicateKeys() {
        let keys = Set(BedcaImporter.duplicateKeys(forBedcaName: "Manzana, golden, con piel")
            + BedcaImporter.duplicateKeys(forBedcaName: "Pan, blanco"))
        #expect(keys.contains(BedcaImporter.duplicateKey(forName: "Manzana")))
        #expect(keys.contains(BedcaImporter.duplicateKey(forName: "Pan blanco")))
        #expect(!keys.contains(BedcaImporter.duplicateKey(forName: "Pizza margarita")))
    }
}

struct FoodSearchTests {
    @Test func accentsAndCaseDoNotMatter() {
        let key = Food.normalize("Bacón, ahumado, a la parrilla")
        #expect(FoodSearch.matches(searchKey: key, query: "bacon"))
        #expect(FoodSearch.matches(searchKey: key, query: "Bacón"))
        #expect(FoodSearch.matches(searchKey: key, query: "BACON ahumado"))
        #expect(!FoodSearch.matches(searchKey: key, query: "bacon crudo"))
    }

    @Test func accentedQueryFindsUnaccentedName() {
        let key = Food.normalize("Platano de Canarias")
        #expect(FoodSearch.matches(searchKey: key, query: "plátano"))
    }
}

/// Pruebas sobre el CSV real. Se ejecutan solo si bedca_foods.csv está en Resources.
@MainActor
struct BundledBedcaTests {
    nonisolated static var hasCSV: Bool { BedcaImporter.bundledURL != nil }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Food.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test(.enabled(if: BundledBedcaTests.hasCSV))
    func importsAlmostAllFoods() throws {
        let url = try #require(BedcaImporter.bundledURL)
        let report = try BedcaImporter.load(url: url)
        #expect(report.foods.count >= 900, "cargados \(report.foods.count), saltados \(report.skipped)")
        #expect(Set(report.foods.map(\.id)).count == report.foods.count, "f_id repetidos")
    }

    /// Las kcal declaradas deben cuadrar con las de los macros (4/4/9, alcohol 7, fibra 2)
    /// con un margen del 20 % en la gran mayoría de alimentos.
    @Test(.enabled(if: BundledBedcaTests.hasCSV))
    func energyIsCoherentWithMacros() throws {
        let url = try #require(BedcaImporter.bundledURL)
        let foods = try BedcaImporter.load(url: url).foods.filter { $0.kcal >= 40 }
        let off = foods.filter { f in
            let fromMacros = f.protein * 4 + f.carbs * 4 + f.fat * 9 + (f.alcohol ?? 0) * 7 + (f.fiber ?? 0) * 2
            return abs(fromMacros - f.kcal) / f.kcal > 0.20
        }
        let share = Double(off.count) / Double(max(foods.count, 1))
        #expect(share < 0.10, "fuera de margen: \(off.prefix(10).map(\.name))")
        #expect(foods.allSatisfy { $0.kcal < 950 }, "ningún alimento pasa de ~900 kcal/100 g")
    }

    @Test(.enabled(if: BundledBedcaTests.hasCSV))
    func seederIsIdempotent() async throws {
        let context = try makeContext()
        let first = await BedcaSeeder.seedIfNeeded(context)
        #expect(first >= 900)
        let second = await BedcaSeeder.seedIfNeeded(context)
        #expect(second == 0)
    }

    @Test(.enabled(if: BundledBedcaTests.hasCSV))
    func catalogHasNoDuplicatesWithFoodsJSON() async throws {
        let context = try makeContext()
        await FoodCatalog.prepare(context)
        let keys = BedcaSeeder.loadedKeys(in: context)
        let seed = FoodSource.seed.rawValue
        let seeds = try context.fetch(FetchDescriptor<Food>(predicate: #Predicate<Food> { $0.sourceRaw == seed }))
        #expect(seeds.allSatisfy { !keys.contains(BedcaImporter.duplicateKey(forName: $0.name)) })
    }
}
