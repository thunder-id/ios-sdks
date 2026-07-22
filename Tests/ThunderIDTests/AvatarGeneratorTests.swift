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

/// Expected values below were cross-checked against the web SDK's `generateAvatarDataUri.ts`
/// algorithm (same `hashStr`, same `AVATAR_PALETTES` order, same index/angle math) run in Node,
/// to guarantee the two SDKs render byte-identical avatars for the same `(content, colors, shape)`.
final class AvatarGeneratorTests: XCTestCase {

    func testGeneratesExpectedAvatarForAcmeColorsTwo() {
        let avatar = generateAvatar(AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 2))
        XCTAssertEqual(avatar.startColorHex, "#10b981")
        XCTAssertEqual(avatar.endColorHex, "#059669")
        XCTAssertEqual(avatar.angleDegrees, 204)
        XCTAssertEqual(avatar.initials, "AC")
        XCTAssertEqual(avatar.shape, .circle)
        XCTAssertNil(avatar.flatBackgroundHex)
    }

    func testGeneratesExpectedAvatarForEmptyContentDefaultsToApp() {
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .twoLetter, content: "", colors: 0))
        XCTAssertEqual(avatar.startColorHex, "#ef4444")
        XCTAssertEqual(avatar.endColorHex, "#b91c1c")
        XCTAssertEqual(avatar.angleDegrees, 168)
        XCTAssertEqual(avatar.initials, "AP")
        XCTAssertEqual(avatar.shape, .rounded)
    }

    func testGeneratesExpectedAvatarWithNegativeColors() {
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .oneLetter, content: "X", colors: -3))
        XCTAssertEqual(avatar.startColorHex, "#ec4899")
        XCTAssertEqual(avatar.endColorHex, "#be185d")
        XCTAssertEqual(avatar.angleDegrees, 254)
        XCTAssertEqual(avatar.initials, "X")
    }

    func testGeneratesExpectedAvatarForLongerSeed() {
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .twoLetter, content: "TH", colors: 5))
        XCTAssertEqual(avatar.startColorHex, "#3688FF")
        XCTAssertEqual(avatar.endColorHex, "#1d5eb4")
        XCTAssertEqual(avatar.angleDegrees, 352)
        XCTAssertEqual(avatar.initials, "TH")
    }

    /// Seed whose hash (3904868035) has the top bit set: JS's `h >> 4` sign-extends here, so an
    /// unsigned shift would compute a different (wrong) angle than the web SDK.
    func testGeneratesExpectedAvatarForHighBitHashSeed() {
        let avatar = generateAvatar(
            AvatarSpec(shape: .rounded, variant: .twoLetter, content: "ANIMALKEY", colors: 5)
        )
        XCTAssertEqual(avatar.startColorHex, "#FF7300")
        XCTAssertEqual(avatar.endColorHex, "#EF4223")
        XCTAssertEqual(avatar.angleDegrees, 341)
        XCTAssertEqual(avatar.initials, "AN")
    }

    func testOneLetterVariantTruncatesToOneCharacter() {
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .oneLetter, content: "BM", colors: 0))
        XCTAssertEqual(avatar.initials, "B")
    }

    func testTwoLetterVariantTruncatesToTwoCharacters() {
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .twoLetter, content: "BMORE", colors: 0))
        XCTAssertEqual(avatar.initials, "BM")
    }

    func testInitialsAreUppercasedWithoutReExtraction() {
        // content is assumed final: lowercase letters are uppercased, but no alphanumeric filtering
        // is re-applied (unlike deriveAvatarContent, which does filter).
        let avatar = generateAvatar(AvatarSpec(shape: .rounded, variant: .twoLetter, content: "bm", colors: 0))
        XCTAssertEqual(avatar.initials, "BM")
    }

    func testExplicitBackgroundSkipsPaletteLookup() {
        let avatar = generateAvatar(
            AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 2, bg: "#FF5733")
        )
        XCTAssertEqual(avatar.flatBackgroundHex, "#FF5733")
        XCTAssertNil(avatar.startColorHex)
        XCTAssertNil(avatar.endColorHex)
        XCTAssertNil(avatar.angleDegrees)
        XCTAssertEqual(avatar.initials, "AC")
    }

    func testSameSeedIsDeterministic() {
        let first = generateAvatar(AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 2))
        let second = generateAvatar(AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 2))
        XCTAssertEqual(first, second)
    }

    func testDifferentColorsProduceDifferentRotationAndUsuallyDifferentPalette() {
        let first = generateAvatar(AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 0))
        let second = generateAvatar(AvatarSpec(shape: .circle, variant: .twoLetter, content: "AC", colors: 3))
        XCTAssertNotEqual(first.angleDegrees, second.angleDegrees)
    }

    func testAngleAndPaletteIndexStayInBounds() {
        for colors in [-100, -7, 0, 7, 100] {
            let spec = AvatarSpec(shape: .rounded, variant: .twoLetter, content: "AN\(colors)", colors: colors)
            let avatar = generateAvatar(spec)
            XCTAssertGreaterThanOrEqual(avatar.angleDegrees ?? -1, 0)
            XCTAssertLessThan(avatar.angleDegrees ?? 360, 360)
        }
    }

    // MARK: - deriveAvatarContent

    func testDeriveAvatarContentOneLetterExtractsFirstAlphanumeric() {
        XCTAssertEqual(deriveAvatarContent(variant: .oneLetter, seedText: "jane doe"), "J")
    }

    func testDeriveAvatarContentTwoLetterExtractsFirstTwoAlphanumerics() {
        XCTAssertEqual(deriveAvatarContent(variant: .twoLetter, seedText: "jane doe"), "JA")
    }

    func testDeriveAvatarContentFallsBackToAWhenSeedHasNoAlphanumerics() {
        XCTAssertEqual(deriveAvatarContent(variant: .twoLetter, seedText: "!!!"), "A")
        XCTAssertEqual(deriveAvatarContent(variant: .twoLetter, seedText: nil), "A")
        XCTAssertEqual(deriveAvatarContent(variant: .twoLetter, seedText: ""), "A")
    }

    func testDeriveAvatarContentAnonymousAnimalIsDeterministicForSameSeed() {
        let first = deriveAvatarContent(variant: .anonymousAnimal, seedText: "session-123")
        let second = deriveAvatarContent(variant: .anonymousAnimal, seedText: "session-123")
        XCTAssertEqual(first, second)
        XCTAssertTrue(anonymousAnimalNames.contains(first))
    }

    func testDeriveAvatarContentAnonymousAnimalReturnsValidAnimalForEmptySeed() {
        let derived = deriveAvatarContent(variant: .anonymousAnimal, seedText: nil)
        XCTAssertTrue(anonymousAnimalNames.contains(derived))
    }

    func testDeriveAvatarContentAnonymousAnimalDiffersAcrossDifferentSeeds() {
        let first = deriveAvatarContent(variant: .anonymousAnimal, seedText: "seed-one")
        let second = deriveAvatarContent(variant: .anonymousAnimal, seedText: "seed-two-totally-different")
        // Not a strict guarantee (hash collisions are possible), but with 19 buckets these two
        // seeds are chosen specifically to land in different buckets, matching the web SDK's fixture.
        XCTAssertNotEqual(first, second)
    }

    func testDeriveAvatarContentAnonymousEntityIsDeterministicForSameSeed() {
        let first = deriveAvatarContent(variant: .anonymousEntity, seedText: "session-123")
        let second = deriveAvatarContent(variant: .anonymousEntity, seedText: "session-123")
        XCTAssertEqual(first, second)
        XCTAssertTrue(anonymousEntityNames.contains(first))
    }

    func testDeriveAvatarContentAnonymousEntityReturnsValidEntityForEmptySeed() {
        let derived = deriveAvatarContent(variant: .anonymousEntity, seedText: nil)
        XCTAssertTrue(anonymousEntityNames.contains(derived))
    }

    func testDeriveAvatarContentAnonymousEntityDiffersAcrossDifferentSeeds() {
        let first = deriveAvatarContent(variant: .anonymousEntity, seedText: "session-123")
        let second = deriveAvatarContent(variant: .anonymousEntity, seedText: "app-abc123")
        // Not a strict guarantee (hash collisions are possible), but with 36 buckets these two
        // seeds are chosen specifically to land in different buckets.
        XCTAssertNotEqual(first, second)
    }
}
