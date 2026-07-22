/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import XCTest
@testable import ThunderID

final class LogoSpecTests: XCTestCase {

    // MARK: - resolveLogoSpec

    func testResolvesEmojiSpec() {
        XCTAssertEqual(resolveLogoSpec("emoji:🛡️"), .emoji("🛡️"))
    }

    func testResolvesEmptyEmojiGlyph() {
        XCTAssertEqual(resolveLogoSpec("emoji:"), .emoji(""))
    }

    func testResolvesAvatarSpec() {
        let resolved = resolveLogoSpec("avatar:shape=circle,variant=two_letter,content=Acme,colors=2")
        let expected = AvatarSpec(shape: .circle, variant: .twoLetter, content: "Acme", colors: 2)
        XCTAssertEqual(resolved, .avatar(expected))
    }

    func testResolvesAvatarSpecWithExplicitBackground() {
        let resolved = resolveLogoSpec("avatar:shape=rounded,variant=one_letter,content=A,bg=%23FF5733")
        // `parseAvatarParams` does no URL-decoding, `%23FF5733` is the literal (unlikely) raw value.
        let expected = AvatarSpec(shape: .rounded, variant: .oneLetter, content: "A", colors: 0, bg: "%23FF5733")
        XCTAssertEqual(resolved, .avatar(expected))
    }

    func testResolvesAvatarSpecForAnonymousAnimal() {
        let resolved = resolveLogoSpec("avatar:variant=anonymous_animal,content=jackalope")
        let expected = AvatarSpec(shape: .rounded, variant: .anonymousAnimal, content: "jackalope", colors: 0)
        XCTAssertEqual(resolved, .avatar(expected))
    }

    func testAvatarSpecDerivesContentFromFallbackSeedTextWhenContentMissing() {
        let resolved = resolveLogoSpec("avatar:shape=rounded,colors=1", fallbackSeedText: "Acme Corp")
        XCTAssertEqual(resolved, .avatar(AvatarSpec(shape: .rounded, variant: .twoLetter, content: "AC", colors: 1)))
    }

    func testAvatarSpecDerivesAnonymousAnimalContentFromFallbackSeedTextWhenContentMissing() {
        let resolved = resolveLogoSpec("avatar:variant=anonymous_animal", fallbackSeedText: "session-123")
        guard case .avatar(let spec) = resolved else {
            return XCTFail("Expected .avatar, got \(resolved)")
        }
        XCTAssertTrue(anonymousAnimalNames.contains(spec.content))
    }

    func testResolvesAvatarSpecForAnonymousEntity() {
        let resolved = resolveLogoSpec("avatar:variant=anonymous_entity,content=hexagon")
        let expected = AvatarSpec(shape: .rounded, variant: .anonymousEntity, content: "hexagon", colors: 0)
        XCTAssertEqual(resolved, .avatar(expected))
    }

    func testAvatarSpecDerivesAnonymousEntityContentFromFallbackSeedTextWhenContentMissing() {
        let resolved = resolveLogoSpec("avatar:variant=anonymous_entity", fallbackSeedText: "app-abc123")
        guard case .avatar(let spec) = resolved else {
            return XCTFail("Expected .avatar, got \(resolved)")
        }
        XCTAssertTrue(anonymousEntityNames.contains(spec.content))
    }

    func testBareUrlFallsBackToUrlKind() {
        let spec = "https://example.com/logo.png"
        XCTAssertEqual(resolveLogoSpec(spec), .url(spec))
    }

    func testUnrecognizedSchemeFallsBackToUrlKind() {
        XCTAssertEqual(resolveLogoSpec("something:else"), .url("something:else"))
    }

    // MARK: - parseAvatarParams

    func testParseAvatarParamsDefaultsWhenFieldsMissing() {
        let params = parseAvatarParams("avatar:")
        XCTAssertEqual(params, AvatarSpec(shape: .rounded, variant: .twoLetter, content: "", colors: 0))
    }

    func testParseAvatarParamsIgnoresInvalidShape() {
        let params = parseAvatarParams("avatar:shape=triangle,variant=two_letter,content=Acme,colors=2")
        XCTAssertEqual(params.shape, .rounded)
    }

    func testParseAvatarParamsIgnoresInvalidVariant() {
        let params = parseAvatarParams("avatar:shape=circle,variant=three_letter,content=Acme,colors=2")
        XCTAssertEqual(params.variant, .twoLetter)
    }

    func testParseAvatarParamsIgnoresNonIntegerColors() {
        let params = parseAvatarParams("avatar:shape=circle,content=Acme,colors=abc")
        XCTAssertEqual(params.colors, 0)
    }

    func testParseAvatarParamsAcceptsNegativeColors() {
        let params = parseAvatarParams("avatar:shape=circle,content=Acme,colors=-3")
        XCTAssertEqual(params.colors, -3)
    }

    func testParseAvatarParamsParsesBg() {
        let params = parseAvatarParams("avatar:shape=circle,content=Acme,bg=#FF5733")
        XCTAssertEqual(params.bg, "#FF5733")
    }

    func testParseAvatarParamsMissingBgIsNil() {
        let params = parseAvatarParams("avatar:shape=circle,content=Acme")
        XCTAssertNil(params.bg)
    }

    func testParseAvatarParamsEmptyBgIsNil() {
        let params = parseAvatarParams("avatar:shape=circle,content=Acme,bg=")
        XCTAssertNil(params.bg)
    }

    func testParseAvatarParamsParsesAnonymousAnimalVariantAndContent() {
        let params = parseAvatarParams("avatar:variant=anonymous_animal,content=otter")
        XCTAssertEqual(params.variant, .anonymousAnimal)
        XCTAssertEqual(params.content, "otter")
    }

    func testParseAvatarParamsParsesAnonymousEntityVariantAndContent() {
        let params = parseAvatarParams("avatar:variant=anonymous_entity,content=hexagon")
        XCTAssertEqual(params.variant, .anonymousEntity)
        XCTAssertEqual(params.content, "hexagon")
    }

    // MARK: - Curated name catalog (must match the web SDK exactly)

    func testAnonymousAnimalNamesHasExpectedNineteenEntries() {
        let expected: Set<String> = [
            "jackalope", "mink", "otter", "platypus", "quagga", "raccoon", "skunk", "chameleon",
            "dingo", "hedgehog", "dinosaur", "capybara", "chinchilla", "chipmunk", "chupacabra",
            "frog", "giraffe", "hippo", "jackal"
        ]
        XCTAssertEqual(anonymousAnimalNames, expected)
    }

    func testAnonymousEntityNamesHasExpectedThirtySixEntries() {
        let expected: Set<String> = [
            "anchor", "antenna", "anvil", "arch", "bridge", "chevron", "circuit_node", "compass",
            "cube", "diamond", "dome", "gate", "hexagon", "key", "lighthouse", "lock", "obelisk",
            "octagon", "orbit_ring", "parallelogram", "pavilion", "pentagon", "plus_facet", "silo",
            "spiral", "spire", "star", "tower", "townhouse", "triangle_stack", "turbine", "valve",
            "windmill", "bot_head", "brain", "neural_net"
        ]
        XCTAssertEqual(anonymousEntityNames, expected)
    }
}
