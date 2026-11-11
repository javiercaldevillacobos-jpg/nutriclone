import Foundation
import Testing
@testable import NutriClone

struct BarcodeTests {
    @Test func validChecksums() {
        #expect(Barcode.isValidChecksum("3017624010701"))
        #expect(Barcode.isValidChecksum("8480000610218"))
        #expect(Barcode.isValidChecksum("96385074"))
        #expect(!Barcode.isValidChecksum("3017624010702"))
    }

    @Test func normalizeKeepsEANAndRejectsMisreads() {
        #expect(Barcode.normalize("3017624010701") == "3017624010701")
        #expect(Barcode.normalize(" 8480000 610218 ") == "8480000610218")
        #expect(Barcode.normalize("3017624010702") == nil)
        #expect(Barcode.normalize("12345") == nil)
    }

    @Test func upcAIsPaddedToEAN13() {
        #expect(Barcode.normalize("042100005264") == "0042100005264")
    }

    @Test func upcEIsExpanded() {
        #expect(Barcode.expandUPCE("04252614") == "042100005264")
        #expect(Barcode.normalize("04252614", isUPCE: true) == "0042100005264")
        // Sin pista del lector: no cuadra como EAN-8, así que se prueba como UPC-E.
        #expect(Barcode.normalize("04252614") == "0042100005264")
    }
}

// Respuestas reales de la API v2 de Open Food Facts (recortadas), consultadas el 2026-11-11.
private enum OFFFixture {
    static let nutella = #"{"code":"3017624010701","product":{"brands":"Ferrero","code":"3017624010701","generic_name":"","nutriments":{"carbohydrates_100g":57.5,"energy-kcal_100g":539,"energy-kj_100g":2228,"energy_100g":2228,"fat_100g":30.9,"proteins_100g":6.3,"salt_100g":0.1075,"saturated-fat_100g":10.6,"sodium_100g":0.043,"sugars_100g":56.3},"product_name":"Nutella"},"status":1,"status_verbose":"product found"}"#

    static let menestra = #"{"code":"8480000610218","product":{"brands":"Hacendado","code":"8480000610218","nutriments":{"carbohydrates_100g":6.5,"energy-kcal_100g":49,"fat_100g":0.3,"fiber_100g":3.7,"proteins_100g":3.3,"sodium_100g":0.02,"sugars_100g":3.5},"product_name":"Menestra de verduras con habas baby congelado","product_name_es":"Menestra de verduras con habas baby congelado"},"status":1,"status_verbose":"product found"}"#

    /// Solo energía en kJ, números como texto, ración y varias marcas.
    static let kilojoulesOnly = #"{"status":1,"product":{"product_name":"Galletas","brands":"Marca A, Marca B","serving_size":"2 galletas (25 g)","serving_quantity":"25","nutriments":{"energy_100g":"2000","proteins_100g":"7","carbohydrates_100g":70,"fat_100g":18}}}"#

    static let notFound = #"{"code":"8480000999995","status":0,"status_verbose":"product not found"}"#
}

private actor RecordingTransport {
    let status: Int
    let body: String
    private(set) var requests: [URLRequest] = []

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

struct OpenFoodFactsTests {
    @Test func parsesCompleteProduct() throws {
        let product = try #require(try OpenFoodFactsService.parse(Data(OFFFixture.nutella.utf8), barcode: "3017624010701"))
        #expect(product.name == "Nutella")
        #expect(product.brand == "Ferrero")
        #expect(product.kcal == 539)
        #expect(product.protein == 6.3)
        #expect(product.carbs == 57.5)
        #expect(product.fat == 30.9)
        #expect(product.saturatedFat == 10.6)
        #expect(abs((product.sodiumMg ?? 0) - 43) < 0.0001)
        #expect(product.isComplete)
    }

    @Test func prefersSpanishName() throws {
        let product = try #require(try OpenFoodFactsService.parse(Data(OFFFixture.menestra.utf8), barcode: "8480000610218"))
        #expect(product.name == "Menestra de verduras con habas baby congelado")
        #expect(product.fiber == 3.7)
        #expect(product.servingGrams == nil)
    }

    @Test func convertsKilojoulesAndReadsStrings() throws {
        let product = try #require(try OpenFoodFactsService.parse(Data(OFFFixture.kilojoulesOnly.utf8), barcode: "x"))
        #expect(abs((product.kcal ?? 0) - 2000 / 4.184) < 0.01)
        #expect(product.protein == 7)
        #expect(product.brand == "Marca A")
        #expect(product.servingLabel == "2 galletas (25 g)")
        #expect(product.servingGrams == 25)
    }

    @Test func notFoundIsNil() throws {
        #expect(try OpenFoodFactsService.parse(Data(OFFFixture.notFound.utf8), barcode: "8480000999995") == nil)
    }

    @Test func requestHasUserAgentAndFields() async throws {
        let transport = RecordingTransport(status: 200, body: OFFFixture.nutella)
        let service = OpenFoodFactsService(transport: { await transport.send($0) })
        let product = try await service.product(barcode: "3017624010701")
        #expect(product?.name == "Nutella")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/api/v2/product/3017624010701.json")
        #expect(request.url?.query?.contains("fields=") == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("NutriClone/") == true)
    }

    @Test func http404MeansNotFound() async throws {
        let transport = RecordingTransport(status: 404, body: OFFFixture.notFound)
        let service = OpenFoodFactsService(transport: { await transport.send($0) })
        #expect(try await service.product(barcode: "8480000610218") == nil)
    }

    @Test func invalidCodeNeverHitsTheNetwork() async {
        let transport = RecordingTransport(status: 200, body: "{}")
        let service = OpenFoodFactsService(transport: { await transport.send($0) })
        await #expect(throws: OpenFoodFactsError.invalidBarcode) {
            try await service.product(barcode: "3017624010702")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func offlineIsMapped() async {
        let service = OpenFoodFactsService(transport: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: OpenFoodFactsError.offline) {
            try await service.product(barcode: "3017624010701")
        }
    }

    @Test func draftFromProduct() throws {
        let product = try #require(try OpenFoodFactsService.parse(Data(OFFFixture.nutella.utf8), barcode: "3017624010701"))
        let draft = FoodDraft(product: product)
        #expect(draft.source == .openFoodFacts)
        #expect(draft.barcode == "3017624010701")
        #expect(draft.name == "Nutella")
        #expect(draft.kcal == 539)
    }
}
