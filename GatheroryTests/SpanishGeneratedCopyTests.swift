import Foundation
import Testing

struct SpanishGeneratedCopyTests {
    @Test("Generated Home and playlist copy compiles with Spanish translations")
    func generatedCopyHasCompiledSpanishTranslations() throws {
        let stringsPath = try #require(
            Bundle.main.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "es"
            )
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: stringsPath))
        let strings = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        )
        let expectedSpanishValues = [
            "event.status.draft": "Borrador",
            "Subevent": "Subevento",
            "idea.filter.inbox": "Bandeja de entrada",
            "idea.filter.saved": "Guardadas",
            "idea.filter.passed": "Descartadas",
            "idea.filter.archive": "Archivadas",
            "Happening now": "En curso",
            "Past event": "Evento pasado",
            "All Ideas": "Todas las ideas",
            "%@, filtered": "%@, filtrado",
            "Ready to schedule": "Lista para programar",
            "event.purpose.planning": "Planificación y visitas",
            "event.purpose.experience": "Parte del evento",
            "home.daysAway.one": "Falta 1 día",
            "home.daysAway.many": "Faltan %lld días",
            "home.peopleGoing.one": "1 persona asistirá",
            "home.peopleGoing.many": "Asistirán %lld personas",
            "home.peopleInvited.one": "1 persona invitada",
            "home.peopleInvited.many": "%lld personas invitadas",
            "Who's Coming": "Quién viene",
            "Other": "Otro",
            "idea.music.songCount.one": "1 canción",
            "idea.music.songCount.many": "%lld canciones",
            "idea.music.sharedPlaylist": "Lista compartida",
            "idea.submittedBy": "De %@",
        ]

        for (key, expectedValue) in expectedSpanishValues {
            #expect(strings[key] == expectedValue)
        }
    }
}
